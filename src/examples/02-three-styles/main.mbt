///|
/// The same two routes, registered three ways, answering the same bytes.
///
///     moon run src/examples/02-three-styles --target native
#coverage.skip
async fn main {
  let forms = [
    ("function", function_app()),
    ("type", view_app("hello")),
    ("annotation", annotation_app()),
  ]
  for form in forms {
    let (name, app) = form
    let ping = app.handle({
      http_method: "GET",
      path: "/ping",
      query_string: b"",
      headers: [],
      body: b"",
    })
    let greet = app.handle({
      http_method: "GET",
      path: "/greet/Ada",
      query_string: b"",
      headers: [],
      body: b"",
    })
    println(
      name +
      ": /ping -> " +
      ping.status.to_string() +
      " " +
      @utf8.decode_lossy(ping.body) +
      ", /greet/Ada -> " +
      greet.status.to_string() +
      " " +
      @utf8.decode_lossy(greet.body),
    )
  }
}
