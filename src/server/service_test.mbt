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
/// A database file of this test's own, in the system temporary directory: a test
/// run must not leave anything behind in the working tree, and two tests that run
/// at the same time must not share a file.
fn temp_db(name : String) -> String {
  let dir = match @env.get_env_var("TMPDIR") {
    Some(d) => d
    None =>
      match @env.get_env_var("TEMP") {
        Some(d) => d
        None => @env.get_env_var("TMP").unwrap_or(".")
      }
  }
  dir + "/" + name
}

///|
/// The greet acceptance: mooncat serves the assembled moonzero/moonapi app on a
/// real socket, a real async HTTP client walks the whole chain, and every hop is
/// asserted. `/ping` answers pong (through the request-id middleware), `/users`
/// persists to SQLite and reads back through the mctl-generated model, and
/// `/openapi.json` is a valid document. This is the "it all works together over
/// the wire" proof, not a mock.
async test "greet e2e: assembled server answers over the wire and persists to SQLite" {
  @async.with_task_group(g => {
    let db_path = temp_db("greet_e2e_test.db")
    // Clean slate so the run is deterministic across CI re-runs.
    let setup = @sqlite.SqliteDriver::open(db_path)
    setup.exec_script("DROP TABLE IF EXISTS user;")
    setup.close()
    let task = g.spawn(() => @server.serve_greet(port=18096, db_path~))
    @async.sleep(300)

    // GET /ping -> 200 "pong", with the request-id middleware header.
    let (ping, pbody) = @http.get("http://127.0.0.1:18096/ping")
    assert_eq(ping.code, 200)
    assert_eq(pbody.text(), "pong")
    assert_eq(ping.headers.get("x-request-id"), Some("greet-1"))

    // POST /users {name} -> 201 created; capture the assigned id.
    let (created, cbody) = @http.post(
      "http://127.0.0.1:18096/users", "{\"name\":\"Ada\"}",
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

    // POST /graphql -> the greeting, executed by moongql on the SAME mooncat
    // server as the REST routes. The greeting text is mutation-guarded: break the
    // resolver and this assertion goes red. The content-type is not decoration:
    // moongql follows GraphQL-over-HTTP and answers a POST without one with a 415
    // rather than guessing what the bytes are.
    let (gql, gqlbody) = @http.post(
      "http://127.0.0.1:18096/graphql",
      "{\"query\":\"{ greeting(name: \\\"Ada\\\") }\"}",
      headers={ "content-type": "application/json" },
    )
    assert_eq(gql.code, 200)
    assert_eq(gqlbody.json(), { "data": { "greeting": "Hello, Ada" } })
    task.cancel()
  })
}

///|
/// The refusal paths, on the same assembled server: a body without `name`, a body
/// that is not JSON, and an id that is not a number are answered before they reach
/// the database, and the status each one answers is the one a client sees.
async test "greet e2e: an unusable request is refused with its own status" {
  @async.with_task_group(g => {
    let db_path = temp_db("greet_refusal_test.db")
    let setup = @sqlite.SqliteDriver::open(db_path)
    setup.exec_script("DROP TABLE IF EXISTS user;")
    setup.close()
    let task = g.spawn(() => @server.serve_greet(port=18097, db_path~))
    @async.sleep(300)

    // A JSON object without `name` -> 422, and the detail names the field.
    let (empty, ebody) = @http.post("http://127.0.0.1:18097/users", "{}")
    assert_eq(empty.code, 422)
    assert_eq(json_str(ebody.json(), "detail"), Some("field required: name"))

    // A body that is not JSON at all -> the same 422, never a 500.
    let (broken, _bb) = @http.post("http://127.0.0.1:18097/users", "not json")
    assert_eq(broken.code, 422)

    // `name` present but not a string -> 422: the reader does not coerce.
    let (typed, _tb) = @http.post(
      "http://127.0.0.1:18097/users", "{\"name\":7}",
    )
    assert_eq(typed.code, 422)

    // A non-numeric id -> 400 rather than a query against SQLite.
    let (bad_id, _ib) = @http.get("http://127.0.0.1:18097/users/abc")
    assert_eq(bad_id.code, 400)

    // The refusal carries the middleware header too, so a log line can pair the
    // request with its answer whichever way it went.
    assert_eq(bad_id.headers.get("x-request-id"), Some("greet-1"))

    // A path that is not routed -> 404, and a method a path does not answer -> 405
    // whose Allow names the ones it does.
    let (nowhere, _nb) = @http.get("http://127.0.0.1:18097/nope")
    assert_eq(nowhere.code, 404)
    let (wrong_method, _wb) = @http.request(
      "http://127.0.0.1:18097/ping",
      Delete,
      {},
      b"",
    )
    assert_eq(wrong_method.code, 405)
    assert_eq(
      wrong_method.headers.get("allow").unwrap_or("").contains("GET"),
      true,
    )
    task.cancel()
  })
}

///|
/// The documentation the same application publishes: the document is built from
/// the routes at the moment it is read, the readers are served beside it, and the
/// readers stay out of the document they describe.
async test "greet e2e: the document describes the routes and not its readers" {
  @async.with_task_group(g => {
    let db_path = temp_db("greet_docs_test.db")
    let setup = @sqlite.SqliteDriver::open(db_path)
    setup.exec_script("DROP TABLE IF EXISTS user;")
    setup.close()
    let task = g.spawn(() => @server.serve_greet(port=18098, db_path~))
    @async.sleep(300)

    let (doc, body) = @http.get("http://127.0.0.1:18098/openapi.json")
    assert_eq(doc.code, 200)
    let text = body.text()
    // The title reaches the document from `App::describe`, not from a literal.
    assert_eq(text.contains("\"title\":\"greet\""), true)
    assert_eq(text.contains("/graphql"), true)
    assert_eq(text.contains("/users/{id}"), true)
    // A reader page is not an operation.
    assert_eq(text.contains("\"/docs\""), false)

    // `/docs` is a page, and it reads the document this app publishes.
    let (page, pbody) = @http.get("http://127.0.0.1:18098/docs")
    assert_eq(page.code, 200)
    assert_eq(
      page.headers.get("content-type"),
      Some("text/html; charset=utf-8"),
    )
    assert_eq(pbody.text().contains("/openapi.json"), true)
    task.cancel()
  })
}

///|
/// GraphQL over HTTP: the content type is required, and a query the schema does
/// not know comes back as a GraphQL error document rather than an HTTP error.
async test "greet e2e: graphql demands its content type and reports its errors" {
  @async.with_task_group(g => {
    let db_path = temp_db("greet_graphql_test.db")
    let setup = @sqlite.SqliteDriver::open(db_path)
    setup.exec_script("DROP TABLE IF EXISTS user;")
    setup.close()
    let task = g.spawn(() => @server.serve_greet(port=18099, db_path~))
    @async.sleep(300)

    // No content-type -> 415, per GraphQL-over-HTTP.
    let (refused, _rb) = @http.post(
      "http://127.0.0.1:18099/graphql", "{\"query\":\"{ greeting(name: \\\"Ada\\\") }\"}",
    )
    assert_eq(refused.code, 415)

    // An unknown field -> 200 with an `errors` array, the shape a GraphQL client
    // reads, and no `data`.
    let (bad, body) = @http.post(
      "http://127.0.0.1:18099/graphql",
      "{\"query\":\"{ farewell(name: \\\"Ada\\\") }\"}",
      headers={ "content-type": "application/json" },
    )
    assert_eq(bad.code, 200)
    match body.json() {
      Object(m) => assert_eq(m.get("errors") is Some(_), true)
      _ => abort("a graphql error document is a JSON object")
    }

    // The same field the schema does have, so the leg is proven both ways.
    let (good, gbody) = @http.post(
      "http://127.0.0.1:18099/graphql",
      "{\"query\":\"{ greeting(name: \\\"Grace\\\") }\"}",
      headers={ "content-type": "application/json" },
    )
    assert_eq(good.code, 200)
    assert_eq(gbody.json(), { "data": { "greeting": "Hello, Grace" } })
    task.cancel()
  })
}
