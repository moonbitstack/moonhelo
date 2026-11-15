///|
/// `parse_int` takes a decimal path segment and nothing else: a sign, a space, a
/// suffix or an empty string is a refusal, so `/users/abc` never reaches SQLite.
test "parse_int: digits only" {
  assert_eq(parse_int("0"), Some(0))
  assert_eq(parse_int("42"), Some(42))
  assert_eq(parse_int("007"), Some(7))
  assert_eq(parse_int(""), None)
  assert_eq(parse_int("abc"), None)
  assert_eq(parse_int("1a"), None)
  assert_eq(parse_int("-1"), None)
  assert_eq(parse_int(" 1"), None)
  assert_eq(parse_int("1.0"), None)
}

///|
/// `parse_name` reads one field out of a JSON object and refuses everything else:
/// a missing field, a field of another type, and a body that is not an object or
/// not JSON at all are the same answer, because they are the same 422.
test "parse_name: one string field, or nothing" {
  assert_eq(parse_name(b"{\"name\":\"Ada\"}"), Some("Ada"))
  assert_eq(parse_name(b"{\"name\":\"\"}"), Some(""))
  assert_eq(parse_name(b"{\"other\":\"Ada\"}"), None)
  assert_eq(parse_name(b"{\"name\":7}"), None)
  assert_eq(parse_name(b"{\"name\":null}"), None)
  assert_eq(parse_name(b"[\"Ada\"]"), None)
  assert_eq(parse_name(b"not json"), None)
  assert_eq(parse_name(b""), None)
}

///|
/// The response bodies are the shapes a client reads: `{id, name}` for a user and
/// `{detail}` for a refusal, with the status the handler chose.
test "json bodies keep their shape" {
  let user = user_json(7, "Ada")
  match user {
    Object(m) => {
      match m.get("id") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 7)
        _ => abort("id is not a number")
      }
      match m.get("name") {
        Some(String(s)) => assert_eq(s, "Ada")
        _ => abort("name is not a string")
      }
      assert_eq(m.length(), 2)
    }
    _ => abort("a user is a JSON object")
  }
  let refused = error_json(422, "field required: name")
  assert_eq(refused.status, 422)
  let detail = match
    @moonjson.loads(@utf8.decode_lossy(refused.body), @moonjson.strict) {
    Object(m) =>
      match m.get("detail") {
        Some(String(s)) => s
        _ => abort("a refusal names its detail")
      }
    _ => abort("a refusal is a JSON object")
  }
  assert_eq(detail, "field required: name")
}
