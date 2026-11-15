///|
/// One call, one line, written by the layer the deployment added — not by the
/// handler, which does not know it is being logged.
///
///     moon run src/examples/04-access-log --target native
async fn main {
  let lines : Array[String] = []
  // The process logger hides anything below `Severe` until told otherwise, which
  // is why a freshly started service looks silent.
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
  println(lines.join("\n"))
}
