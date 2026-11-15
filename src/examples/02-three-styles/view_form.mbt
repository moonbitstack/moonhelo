///|
/// A value that answers one path. Whatever the handler needs travels with the
/// value instead of being captured by a closure, which is what makes this form
/// worth reaching for once a route owns a resource.
struct Greeter {
  greeting : String
}

///|
impl @moonapi.View for Greeter with fn get(self) {
  Some(ctx => {
    @moonapi.text(200, self.greeting + ", " + ctx.param("id").unwrap_or("?"))
  })
}

///|
/// The type form: the path is registered with the value that answers it.
pub fn view_app(greeting : String) -> @moonapi.App {
  let app = @moonapi.App::new()
  app.get("/ping", _ctx => @moonapi.text(200, "pong"), summary="health check")
  app.view("/greet/{id}", Greeter::{ greeting, })
  app
}
