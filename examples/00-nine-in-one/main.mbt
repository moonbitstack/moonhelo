///|
/// The whole moon* suite in one breath. A single greeting for `heke1228` is carried
/// through all nine libraries, one line each: the `.api` spec that describes it
/// (moonctl), the ASGI request that requests it (moonasgi), the go-zero-style route
/// group that assembles the service (moonzero) on the typed framework that answers it
/// (moonapi), the address the native server would bind (mooncat), the SQL that would
/// persist it (moonorm), the gRPC DATA frame that would carry it (moonrpc), the
/// GraphQL query that would fetch it (moongql), and the agent prompt that would speak
/// it (moonkoog). Everything runs in-process, no socket, no database.
///
///     moon run examples/00-nine-in-one --target native
///
/// `raise` because since 0.7.0 moonctl reports a malformed spec instead of quietly
/// parsing less of it, and a demo that swallowed that would be demonstrating the old
/// behaviour.
#coverage.skip
fn main raise {
  let who = "heke1228"

  // 1. moonctl (<- goctl): the .api spec that declares the greet service.
  let spec = @moonctl.parse(
    (
      #|service greet {
      #|  get /api/v1/greet/:name greet_one "greet a user"
      #|}
      #|
      #|type Greet {
      #|  name: string
      #|}
    ),
  )
  println(
    "moonctl : parsed service '\{spec.service}' — \{spec.routes.length()} route, \{spec.types.length()} type",
  )

  // 2. moonasgi (<- ASGI 3.0): the request the whole stack speaks.
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/api/v1/greet/" + who,
    query_string: b"",
    headers: [],
    body: b"",
  }
  println("moonasgi: scope \{req.http_method} \{req.path}")

  // 3. moonzero (<- go-zero) assembles the group on 4. moonapi (<- FastAPI), which
  //    answers the typed route. One `handle` drives both.
  let app = @moonapi.App::new()
  let api = @moonzero.Group::new(app, "/api/v1")
  api.get("/greet/:name", ctx => {
    @moonapi.text(200, "Bonjour, " + ctx.param("name").unwrap() + "!")
  })
  let resp = app.handle(req)
  let body = @utf8.decode_lossy(resp.body[:])
  println("moonzero: group /api/v1 mounted the route")
  println("moonapi : \{resp.status} \{body}")

  // 5. mooncat (<- uvicorn): where the native server would bind this app.
  let cfg = @mooncat.Config::new(host="127.0.0.1", port=8000)
  println("mooncat : would serve on http://\{cfg.bind()}")

  // 6. moonorm (<- SQLAlchemy): the SQL that persists the greeting.
  let (sql, params) = @moonorm.select("greets")
    .column("id")
    .column("name")
    .eq("name", @moondb.Text(who))
    .build()
  ignore(params)
  println("moonorm : \{sql}")

  // 7. moonrpc (<- gRPC): the greeting as a DATA frame on the HTTP/2 wire.
  let frame = @moonrpc.Frame::Data(
    stream_id=1,
    data=@utf8.encode(body),
    end_stream=true,
    padding=0,
  )
  println("moonrpc : DATA frame \{frame.encode().length()} octets on stream 1")

  // 8. moongql (<- strawberry): the same greeting as a GraphQL field.
  let schema = @moongql.Schema::new()
  schema
  .object("Query")
  .field_args(
    "greet",
    [("name", @moongql.Scalar("String"))],
    @moongql.NonNull(@moongql.Scalar("String")),
  )
  let resolvers = @moongql.Resolvers::new()
  resolvers.field("Query", "greet", info => {
    let n = match info.arg("name") {
      String(s) => s
      _ => "?"
    }
    ("Bonjour, " + n + "!").to_json()
  })
  let gql = @moongql.execute(
    schema,
    resolvers,
    "{ greet(name: \"" + who + "\") }",
  ).stringify()
  println("moongql : \{gql}")

  // 9. moonkoog (<- Koog): the agent prompt that would speak the greeting.
  let prompt = @prompt.PromptBuilder::new(id="greet-233")
    .system("You are a terse greeter.")
    .user("Greet " + who)
    .build()
  println(
    "moonkoog: prompt '\{prompt.id}' — \{prompt.messages.length()} messages",
  )
}
