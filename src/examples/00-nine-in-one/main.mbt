///|
/// The whole suite in one breath. A single greeting for `heke1228` is carried
/// through nine libraries, one line each: the `.api` spec that describes it
/// (moonctl), the ASGI request that asks for it (moonasgi), the go-zero-style
/// route group that assembles the service (moonzero) on the typed framework that
/// answers it (moonapi), the address the native server would bind (mooncat), the
/// SQL that would persist it (moonorm), the gRPC message that would carry it
/// (moonrpc), the GraphQL query that would fetch it (moongql), and the prompt a
/// model would answer (moonmuse, with a scripted model — no network, no key).
/// Everything runs in-process: no socket, no database.
///
///     moon run src/examples/00-nine-in-one --target native
///
/// `raise` because moonctl reports a malformed spec instead of quietly parsing
/// less of it, and a demo that swallowed that would be demonstrating the old
/// behaviour.
#coverage.skip
async fn main {
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
    "moonctl : parsed service '" +
    spec.service +
    "' — " +
    spec.routes.length().to_string() +
    " route, " +
    spec.types.length().to_string() +
    " type",
  )

  // 2. moonasgi (<- ASGI 3.0): the request the whole stack speaks.
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/api/v1/greet/" + who,
    query_string: b"",
    headers: [],
    body: b"",
  }
  println("moonasgi: scope " + req.http_method + " " + req.path)

  // 3. moonzero (<- go-zero) assembles the group on 4. moonapi (<- FastAPI), which
  //    answers the typed route. One `handle` drives both.
  let app = @moonapi.App::new()
  let api = @zero.Group::new(app, "/api/v1")
  api.get("/greet/{name}", ctx => {
    @moonapi.text(200, "Bonjour, " + ctx.param("name").unwrap_or("?") + "!")
  })
  api.get("/greet/{name}/card", ctx => {
    ctx.serve(
      @utf8.encode("Bonjour, " + ctx.param("name").unwrap_or("?") + "!"),
      filename="card.txt",
    )
  })
  let resp = app.handle(req)
  let body = @utf8.decode_lossy(resp.body)
  println("moonzero: group /api/v1 mounted the route")
  println("moonapi : " + resp.status.to_string() + " " + body)

  // The same route asked for twice. `serve` weighs the conditional fields, so
  // the second answer is a status rather than a body.
  let card = app.handle({ ..req, path: req.path + "/card", })
  let tag = card.header("etag").unwrap_or("")
  let again = app.handle({
    ..req,
    path: req.path + "/card",
    headers: [("if-none-match", tag)],
  })
  println(
    "moonapi : " +
    card.status.to_string() +
    " then " +
    again.status.to_string() +
    " — " +
    again.body.length().to_string() +
    " octets the second time",
  )

  // 5. mooncat (<- uvicorn): where the native server would bind this app.
  let cfg = @mooncat.Config::new(host="127.0.0.1", port=12000)
  println("mooncat : would serve on http://" + cfg.bind())

  // 6. moonorm (<- SQLAlchemy): the SQL that persists the greeting.
  let (sql, params) = @query.select("greets")
    .column("id")
    .column("name")
    .eq("name", @moondb.Text(who))
    .build()
  ignore(params)
  println("moonorm : " + sql)

  // 7. moonrpc (<- gRPC): the greeting as a length-prefixed gRPC message, the
  //    payload an HTTP/2 DATA frame carries.
  let message = @moonrpc.encode_message(@utf8.encode(body))
  println("moonrpc : gRPC message " + message.length().to_string() + " octets")

  // 8. moongql (<- strawberry): the same greeting as a GraphQL field.
  let schema = @gql.Schema::new()
  schema
  .object("Query")
  .field_args("greet", [("name", Scalar("String"))], NonNull(Scalar("String")))
  let resolvers = @gql.Resolvers::new()
  resolvers.field("Query", "greet", info => {
    let n = match info.arg("name") {
      String(s) => s
      _ => "?"
    }
    Json("Bonjour, " + n + "!")
  })
  let gql = @gql.execute(schema, resolvers, "{ greet(name: \"" + who + "\") }")
  println("moongql : " + gql.stringify())

  // 9. moonmuse (<- one contract for every model): the prompt, written as a
  //    template and rendered, and the answer, from a scripted provider — the
  //    same call reaches a real vendor once a client replaces the provider.
  let template = @prompt.Template::new("Greet {{ who }} in one sentence.")
  let asked = template.render(@prompt.values([("who", Json(who))]))
  let provider : &@moonmuse.Provider = @fake.Fake::text("Bonjour, " + who + "!")
  let reply = provider.chat(
    @moonmuse.Request::new("scripted", [@moonmuse.Message::user(asked)]),
  )
  println("moonmuse: prompt '" + asked + "'")
  println("moonmuse: " + reply.text())
}
