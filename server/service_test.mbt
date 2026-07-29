///|
/// The string field `key` of a JSON object, for asserting on response bodies.
fn json_str(j : Json, key : String) -> String? {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// The greet acceptance: mooncat serves the assembled moonzero/moonapi app on a
/// real socket, a real async HTTP client walks the whole chain, and every hop is
/// asserted. `/ping` answers pong (through the request-id middleware), `/users`
/// persists to SQLite and reads back through the mctl-generated model, and
/// `/openapi.json` is a valid document. This is the "it all works together over
/// the wire" DoD, not a mock.
async test "greet e2e: assembled server answers over the wire and persists to SQLite" {
  @async.with_task_group(g => {
    let db_path = "greet_e2e_test.db"
    // Clean slate so the run is deterministic across CI re-runs.
    let setup = @sqlite.SqliteDriver::open(db_path)
    setup.exec_script("DROP TABLE IF EXISTS user;")
    setup.close()
    let task = g.spawn(() => serve_greet(port=18096, db_path~))
    @async.sleep(300)

    // GET /ping -> 200 "pong", with the request-id middleware header.
    let (ping, pbody) = @http.get("http://127.0.0.1:18096/ping")
    assert_eq(ping.code, 200)
    assert_eq(pbody.text(), "pong")
    assert_eq(ping.headers.get("x-request-id"), Some("greet-1"))

    // POST /users {name} -> 201 created; capture the assigned id.
    let (created, cbody) = @http.post(
      "http://127.0.0.1:18096/users",
      "{\"name\":\"Ada\"}",
    )
    assert_eq(created.code, 201)
    let created_json = cbody.json()
    assert_eq(json_str(created_json, "name"), Some("Ada"))
    let id = match created_json {
      Object(m) =>
        match m.get("id") {
          Some(Number(n, ..)) => n.to_int()
          _ => abort("created user has no numeric id")
        }
      _ => abort("created user is not a JSON object")
    }

    // GET /users/:id -> 200, the same user read back through the generated model.
    let (got, gbody) = @http.get(
      "http://127.0.0.1:18096/users/" + id.to_string(),
    )
    assert_eq(got.code, 200)
    assert_eq(json_str(gbody.json(), "name"), Some("Ada"))

    // A row that does not exist -> 404 through the same path.
    let (miss, _mb) = @http.get("http://127.0.0.1:18096/users/999999")
    assert_eq(miss.code, 404)

    // GET /openapi.json -> a valid OpenAPI document carrying /ping and /users.
    let (spec, sbody) = @http.get("http://127.0.0.1:18096/openapi.json")
    assert_eq(spec.code, 200)
    let doc = sbody.json()
    match doc {
      Object(m) => {
        assert_eq(m.get("openapi") is Some(_), true)
        match m.get("paths") {
          Some(Object(paths)) => {
            assert_eq(paths.get("/ping") is Some(_), true)
            assert_eq(paths.get("/users") is Some(_), true)
          }
          _ => abort("openapi document has no paths object")
        }
      }
      _ => abort("openapi document is not a JSON object")
    }
    task.cancel()
  })
}
