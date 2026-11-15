///|
/// The log is process state, so one test drives it end to end rather than two
/// tests racing each other for it.
///
/// Two calls, two lines, both naming the method and the path. The one that went
/// to a route that does not exist is logged too — a 404 is a request that
/// arrived, and an access log that hides it is hiding the scan.
///
/// Then the level drops below `Info`, and the same call writes nothing: the level
/// is a gate, not a filter applied after the fact.
async test "one line per call, and the level gates the write" {
  let lines : Array[String] = []
  @zero.set_log_level(Info)
  @zero.set_log_writer(line => lines.push(line))
  let app = @moonapi.App::new()
  app.get("/ping", _ctx => @moonapi.text(200, "pong"))
  let asgi = @zero.Server::new(@zero.ServiceConf::new(name="greet"), app)
    .use_(@zero.logging)
    .to_asgi()
  let client = @testing.Client::new(asgi)
  ignore(client.get("/ping"))
  ignore(client.get("/nope"))
  assert_eq(lines.length(), 2)
  assert_eq(lines[0].contains("GET /ping"), true)
  assert_eq(lines[1].contains("GET /nope"), true)
  lines.clear()
  @zero.set_log_level(Severe)
  ignore(client.get("/ping"))
  assert_eq(lines.length(), 0)
  @zero.set_log_level(Info)
}
