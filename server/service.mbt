///|
/// Pull `name` out of a JSON request body, or `None` when the body is not an
/// object with a string `name`. A missing/malformed name is the 422 path.
fn parse_name(body : Bytes) -> String? {
  let parsed = try @json.parse(@utf8.decode_lossy(body[:])) catch {
    _ => return None
  } noraise {
    v => v
  }
  match parsed {
    Object(m) =>
      match m.get("name") {
        Some(String(n)) => Some(n)
        _ => None
      }
    _ => None
  }
}

///|
/// Parse a decimal id path segment. Rejects anything that is not all digits so a
/// bad `:id` answers 400 rather than reaching the database.
fn parse_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut acc = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 48 || c > 57 {
      return None
    }
    acc = acc * 10 + (c - 48)
  }
  Some(acc)
}

///|
/// A `{id, name}` JSON object for a user.
fn user_json(id : Int, name : String) -> Json {
  let m : Map[String, Json] = Map([
    ("id", id.to_json()),
    ("name", name.to_json()),
  ])
  m.to_json()
}

///|
/// A `{detail}` JSON error response with an explicit status.
fn error_json(status : Int, detail : String) -> @moonasgi.Response {
  let m : Map[String, Json] = Map([("detail", detail.to_json())])
  @moonapi.json(status, m.to_json())
}

///|
/// POST /users: read `{name}` off the body, insert a row (SQLite assigns the
/// autoincrement id), and echo the created user back with 201. The insert binds
/// `name` as a parameter, so the value never reaches the SQL text.
fn handle_create_user(
  sess : @moonorm.Session,
  ctx : @moonapi.Context,
) -> @moonasgi.Response {
  let name = match parse_name(ctx.request.body) {
    Some(n) => n
    None => return error_json(422, "field required: name")
  }
  let res = try
    sess.execute("INSERT INTO user (name) VALUES (?)", [@moondb.Text(name)])
  catch {
    e => return error_json(500, "insert failed: " + e.to_string())
  } noraise {
    v => v
  }
  @moonapi.json(201, user_json(res.last_insert_id.to_int(), name))
}

///|
/// GET /users/:id: decode the id, read the row back through the mctl-generated
/// `user_model`, and return the user or 404. Reading through the generated model
/// is the "the generated code runs, not just compiles" half of the DoD.
fn handle_get_user(
  sess : @moonorm.Session,
  ctx : @moonapi.Context,
) -> @moonasgi.Response {
  let id = match ctx.param("id") {
    Some(s) =>
      match parse_int(s) {
        Some(i) => i
        None => return error_json(400, "invalid id")
      }
    None => return error_json(400, "missing id")
  }
  let rows = try
    sess.fetch_as(
      @genmodel.user_model,
      @genmodel.user_model.select().eq("id", @moondb.Int(id)),
    )
  catch {
    e => return error_json(500, "query failed: " + e.to_string())
  } noraise {
    v => v
  }
  if rows.length() == 0 {
    return error_json(404, "user not found")
  }
  let u = rows[0]
  @moonapi.json(200, user_json(u.id, u.name))
}

///|
/// Build the greet moonapi app over an open Session: the request-id middleware,
/// the three business routes, and a `/openapi.json` route serving the document
/// walked from the routes registered before it. The real handlers replace the
/// mctl stubs while keeping the generated model as the persistence layer.
fn build_app(sess : @moonorm.Session) -> @moonapi.App {
  let app = @moonapi.App::new()
  let request_id : @moonasgi.Middleware = fn(next) {
    fn(req) {
      let resp = next(req)
      @moonasgi.Response::new(
        resp.status,
        [("x-request-id", "greet-1"), ..resp.headers],
        resp.body,
      )
    }
  }
  app.middleware(request_id)
  app.get("/ping", _ctx => @moonapi.text(200, "pong"), summary="health check")
  app.post(
    "/users",
    ctx => handle_create_user(sess, ctx),
    summary="create a user",
  )
  app.get(
    "/users/:id",
    ctx => handle_get_user(sess, ctx),
    summary="fetch a user by id",
  )
  let gql = gql_handler()
  app.post("/graphql", ctx => gql(ctx.request), summary="GraphQL query")
  app.get("/graphql", ctx => gql(ctx.request), summary="GraphiQL")
  let doc = app.openapi(title="greet", api_version="0.1.0")
  app.get("/openapi.json", _ctx => @moonapi.json(200, doc), summary="OpenAPI")
  app
}

///|
/// Assemble the moonzero Server over the moonapi app and lower it to an AsgiApp,
/// adding go-zero's request-logging middleware around the router.
pub fn assemble(sess : @moonorm.Session) -> @moonasgi.AsgiApp {
  let conf = @zero.ServiceConf::new(name="greet")
  @zero.Server::new(conf, build_app(sess)).use_(@zero.logging).to_asgi()
}

///|
/// Open the database at `db_path`, run the migration (create the `user` table),
/// assemble the app, and serve it over native HTTP with mooncat. Blocks in the
/// accept loop until the running task is cancelled.
pub async fn serve_greet(
  host? : String = "127.0.0.1",
  port? : Int = 8080,
  db_path? : String = "greet.db",
) -> Unit {
  let db = @sqlite.SqliteDriver::open(db_path)
  let sess = @moonorm.Session::new(db)
  @genmodel.user_up(sess) |> ignore
  @mooncat.serve(assemble(sess), host~, port~)
}
