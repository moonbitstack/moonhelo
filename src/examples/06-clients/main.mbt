// The service called from outside, the way a client calls it: moonfetch over
// HTTP for the REST routes and the GraphQL field, and an MCP client calling the
// greet tool that the same listener serves at /mcp.
//
//     moon run src/examples/06-clients --target native

///|
/// The port the tour listens on and calls: the family's default.
let port : Int32 = 12000

///|
/// The greeting as a tool a model can call: the words the GraphQL field and the
/// gRPC method answer with, offered over MCP.
fn greeter() -> @moonmcp.Server {
  let mcp = @moonmcp.Server::new("greet", version="0.1.0")
  mcp.tool(
    "greet",
    args => {
      let name = match args.get("name") {
        Some(String(name)) => name
        _ => "stranger"
      }
      Json::string("Hello, " + name)
    },
    description="Greet someone by name",
    input_schema={
      "type": "object",
      "properties": { "name": { "type": "string" } },
      "required": ["name"],
    },
  )
  mcp
}

///|
async fn main {
  let sess = @moonorm.Session::new(@sqlite.SqliteDriver::open(":memory:"))
  @genmodel.user_up(sess) |> ignore
  // One listener, two applications: the MCP endpoint under /mcp, the greet
  // service for every other path.
  let app = @dispatch.mount(
    [("/mcp", greeter().to_asgi(path="/", docs=None))],
    fallback=@server.assemble(sess),
  )
  let base = "http://127.0.0.1:\{port}"
  // The server's own log lines would interleave with the client's, so the tour
  // keeps only what the clients see.
  @zero.set_log_writer(_ => ())
  let config = @config.Config::new(
    port~,
    logger=@config.Logger::new(access=false),
  )
  let listening = @serve.Listening::new()
  @async.with_task_group(group => {
    group.spawn_bg(
      () => @mooncat.serve_config(app, config, listening~),
      no_wait=true,
    )
    ignore(listening.addr())
    let http = @moonfetch.Client::new(base_url=base)
    let ping = http.get("/ping")
    println("GET  /ping     -> \{ping.status} \{ping.text()}")
    let made = http.post(
      "/users",
      body=@moonfetch.Body::Json({ "name": "Ada" }),
    )
    println("POST /users    -> \{made.status} \{made.text()}")
    let read = http.get("/users/1")
    println("GET  /users/1  -> \{read.status} \{read.text()}")
    let field = http.post(
      "/graphql",
      body=@moonfetch.Body::Json({ "query": "{ greeting(name: \"Ada\") }" }),
    )
    println("POST /graphql  -> \{field.status} \{field.text()}")
    let mcp = @client.Client::connect(@http.Http::new(base + "/mcp"))
    let answer = mcp.call_tool("greet", arguments={ "name": "Ada" })
    for block in answer.content {
      if block is Text(text~, ..) {
        println("MCP  greet     -> \{text}")
      }
    }
    mcp.close()
  })
}
