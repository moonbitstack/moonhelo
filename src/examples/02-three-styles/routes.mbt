// The annotation form. `moon.pkg` wires `moonx moonbitstack/moonapi/cmd/routes`
// over this file; the `register(app)` it writes is in routes.g.mbt, which is
// generated at build time and not edited by hand.

///|
#app.get("/ping", summary="health check")
fn ping_route(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "pong")
}

///|
#app.get("/greet/{id}", summary="greet one name")
fn greet_route(ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "hello, " + ctx.param("id").unwrap_or("?"))
}

///|
/// The annotation form as a value: `register(app)` comes from the generator.
pub fn annotation_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  register(app)
  app
}
