///|
/// The greet GraphQL schema: `type Query { greeting(name: String!): String! }`.
fn gql_schema() -> @gql.Schema {
  let schema = @gql.Schema::new()
  let query = schema.object("Query")
  query.field_args(
    "greeting",
    [("name", @gql.NonNull(@gql.Scalar("String")))],
    @gql.NonNull(@gql.Scalar("String")),
  )
  schema
}

///|
/// The greet resolvers: `Query.greeting` greets its `name` argument.
fn gql_resolvers() -> @gql.Resolvers {
  let resolvers = @gql.Resolvers::new()
  resolvers.field("Query", "greeting", info => {
    let name = match info.arg("name") {
      String(s) => s
      _ => ""
    }
    ("Hello, " + name).to_json()
  })
  resolvers
}

///|
/// Map the async HTTP method enum to the ASGI method string.
fn method_str(m : @http.RequestMethod) -> String {
  match m {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
/// The path with any query string stripped.
fn split_path(raw : String) -> String {
  let n = raw.length()
  for i = 0; i < n; i = i + 1 {
    if raw[i] == '?' {
      return raw[0:i].to_owned()
    }
  }
  raw
}

///|
/// A reason phrase for the handful of statuses the GraphQL endpoint returns.
fn reason(code : Int) -> String {
  match code {
    200 => "OK"
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    _ => ""
  }
}

///|
/// Serve the greet GraphQL endpoint over native HTTP: `POST /graphql` executes a
/// query and returns `{ data, errors }`, `GET /graphql` serves GraphiQL. moongql
/// is built against moonasgi 0.5.0, which mooncat is not, so this bridges the
/// moongql handler onto moonbitlang/async's HTTP server directly rather than
/// through mooncat. Blocks in the accept loop until the running task is cancelled.
pub async fn serve_greet_gql(
  host? : String = "127.0.0.1",
  port? : Int = 8090,
) -> Unit {
  let handler = @gql.graphql_handler(gql_schema(), gql_resolvers())
  let server = @http.Server(
    @socket.Addr::parse(host + ":" + port.to_string()),
    reuse_addr=true,
  )
  server.run_forever((request, body_reader, conn) => {
    let buf = @buffer.Buffer()
    for ;; {
      match body_reader.read_some() {
        Some(chunk) => buf.write_bytes(chunk)
        None => break
      }
    }
    let req : @moonasgi.Request = {
      http_method: method_str(request.meth),
      path: split_path(request.path),
      query_string: b"",
      headers: [],
      body: buf.to_bytes(),
    }
    let resp = handler(req)
    let headers : Map[String, String] = Map([])
    for h in resp.headers {
      if h.0 != "content-length" && h.0 != "transfer-encoding" {
        headers[h.0] = h.1
      }
    }
    conn.send_response(resp.status, reason(resp.status), extra_headers=headers)
    conn.write(resp.body)
    conn.end_response()
  })
}
