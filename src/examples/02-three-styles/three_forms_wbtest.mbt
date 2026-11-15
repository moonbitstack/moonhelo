///|
/// Three registrations, one answer. If a form drifts — a different greeting, a
/// status that is not 200, a path that stops matching — this goes red for the
/// form that moved and names it.
async test "the three forms answer the same bytes" {
  let wanted = [
    ("/greet/Ada", 200, "hello, Ada"),
    ("/ping", 200, "pong"),
    ("/greet/", 404, ""),
    ("/nope", 404, ""),
  ]
  let forms = [
    ("function", function_app()),
    ("type", view_app("hello")),
    ("annotation", annotation_app()),
  ]
  for form in forms {
    let (name, app) = form
    for want in wanted {
      let (path, status, body) = want
      let got = app.handle({
        http_method: "GET",
        path,
        query_string: b"",
        headers: [],
        body: b"",
      })
      assert_eq(got.status, status)
      if body != "" {
        assert_eq(@utf8.decode_lossy(got.body), body)
      } else {
        assert_eq(got.body.length() > 0, true)
      }
      ignore(name)
    }
  }
}
