///|
/// The function form: the handler sits next to its path, and the path is the
/// first thing you read.
pub fn function_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  app.get("/ping", ctx => ping(ctx), summary="health check")
  app.get("/greet/{id}", ctx => greet_one(ctx), summary="greet one name")
  app
}

///|
/// The answers both forms share, so the three of them cannot drift in what they
/// say — only in how the route is registered.
fn ping(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "pong")
}

///|
fn greet_one(ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "hello, " + ctx.param("id").unwrap_or("?"))
}
