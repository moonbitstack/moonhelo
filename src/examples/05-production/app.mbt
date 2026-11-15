// The service: the ledger's routes, and around them the five things a deployment
// adds. Each is registered where a request meets it, not in the handler it wraps.

///|
/// What the process owns and a handler borrows. A handler that opened its own
/// session would be a handler deciding how many connections there are.
pub struct Deps {
  sess : @moonorm.Session
  metrics : @zero.ServerMetrics
  audit : @zero.TaskRunner[String]
}

///|
fn wallet_json(w : Wallet) -> Json {
  Json({
    "id": Json::number(w.id.to_double()),
    "owner": Json::string(w.owner),
    "cents": Json::number(w.cents.to_double()),
  })
}

///|
fn error_json(status : Int32, detail : String) -> @moonasgi.Response {
  @moonapi.json(status, Json({ "detail": Json::string(detail) }))
}

///|
/// A path or body number, as an id. Anything that is not all digits is not an id,
/// so it never reaches the database.
fn parse_id(s : String) -> Int64? {
  if s.length() == 0 {
    return None
  }
  let mut acc : Int64 = 0L
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 48 || c > 57 {
      return None
    }
    acc = acc * 10L + (c - 48).to_int64()
  }
  Some(acc)
}

///|
/// Read an integer field off a body the endpoint has already validated: the type
/// is a promise the descriptor kept, so the only remaining case is absence.
fn int_field(ctx : @moonapi.Context, name : String) -> Int64? {
  match ctx.json_field(name) {
    Some(Json::Number(n, ..)) => Some(n.to_int64())
    _ => None
  }
}

///|
/// One wallet, or none — the shape the handlers want, with the driver's error
/// turned into the absence it means here.
fn find_or_none(sess : @moonorm.Session, id : Int64) -> Wallet? {
  try find(sess, id) catch {
    _ => None
  } noraise {
    v => v
  }
}

///|
/// The body a wallet is opened with. `owner` has a floor and a ceiling, `cents` a
/// floor; moonschema enforces them and the same tree is what the OpenAPI document
/// shows a client, so the promise and the check cannot drift apart.
fn new_wallet_body() -> @schema.Schema {
  @schema.Schema::object("NewWallet", [
    @schema.Field::new("owner", @schema.SStr, constraints=[
      @schema.MinLength(2),
      @schema.MaxLength(32),
    ]),
    @schema.Field::new("cents", @schema.SInt, constraints=[@schema.Minimum(0.0)]),
  ])
}

///|
fn transfer_body() -> @schema.Schema {
  @schema.Schema::object("Transfer", [
    @schema.Field::new("from", @schema.SInt, constraints=[@schema.Minimum(1.0)]),
    @schema.Field::new("to", @schema.SInt, constraints=[@schema.Minimum(1.0)]),
    @schema.Field::new("cents", @schema.SInt, constraints=[@schema.Minimum(1.0)]),
  ])
}

///|
/// A page of the ledger. `limit` is clamped by `page`, so a client asking for ten
/// thousand rows gets a hundred rather than an error — a bound the server chose,
/// not one the client has to know.
fn handle_list(deps : Deps, ctx : @moonapi.Context) -> @moonasgi.Response {
  let limit = match ctx.query("limit") {
    Some(s) =>
      match parse_id(s) {
        Some(n) => n.to_int()
        None => 20
      }
    None => 20
  }
  let offset = match ctx.query("offset") {
    Some(s) =>
      match parse_id(s) {
        Some(n) => n.to_int()
        None => 0
      }
    None => 0
  }
  let rows = try page(deps.sess, limit, offset) catch {
    _ => return error_json(500, "query failed")
  } noraise {
    v => v
  }
  let total = try count(deps.sess) catch {
    _ => 0L
  } noraise {
    v => v
  }
  let items : Array[Json] = rows.map(wallet_json)
  let seen = offset + rows.length()
  @moonapi.json(
    200,
    Json({
      "items": Json::array(items),
      "total": Json::number(total.to_double()),
      "next": if seen.to_int64() < total {
        Json::number(seen.to_double())
      } else {
        Json::null()
      },
    }),
  )
}

///|
/// Open a wallet. The descriptor has already refused a short owner or a negative
/// balance, so the handler's remaining job is the insert and the read-back.
fn handle_create(deps : Deps, ctx : @moonapi.Context) -> @moonasgi.Response {
  let owner = match ctx.json_field("owner") {
    Some(Json::String(s)) => s
    _ => return error_json(422, "field required: owner")
  }
  let cents = match int_field(ctx, "cents") {
    Some(n) => n
    None => return error_json(422, "field required: cents")
  }
  let inserted = try
    deps.sess.execute("INSERT INTO wallet (owner, cents) VALUES (?, ?)", [
      @moondb.Text(owner),
      @moondb.Int64(cents),
    ])
  catch {
    _ => return error_json(500, "insert failed")
  } noraise {
    v => v
  }
  let row = find_or_none(deps.sess, inserted.last_insert_id)
  match row {
    Some(w) => @moonapi.json(201, wallet_json(w))
    None => error_json(500, "the row did not come back")
  }
}

///|
/// One wallet. This is the route behind a token, and the handler still checks
/// nothing about authorization: the refusal happened before it was called.
fn handle_one(deps : Deps, ctx : @moonapi.Context) -> @moonasgi.Response {
  let id = match ctx.param("id") {
    Some(s) =>
      match parse_id(s) {
        Some(n) => n
        None => return error_json(400, "invalid id")
      }
    None => return error_json(400, "missing id")
  }
  match find_or_none(deps.sess, id) {
    Some(w) => @moonapi.json(200, wallet_json(w))
    None => error_json(404, "wallet not found")
  }
}

///|
/// Move money between two wallets, then record that it happened. The record is
/// pushed after the commit and handled by another task, so the response does not
/// wait for the write that describes it.
fn handle_transfer(deps : Deps, ctx : @moonapi.Context) -> @moonasgi.Response {
  let from = match int_field(ctx, "from") {
    Some(n) => n
    None => return error_json(422, "field required: from")
  }
  let to = match int_field(ctx, "to") {
    Some(n) => n
    None => return error_json(422, "field required: to")
  }
  let cents = match int_field(ctx, "cents") {
    Some(n) => n
    None => return error_json(422, "field required: cents")
  }
  let moved = try {
    transfer_funds(deps.sess, from, to, cents)
    Ok(())
  } catch {
    e => Err(e)
  }
  match moved {
    Err(_) => error_json(409, "the move would break a rule of the ledger")
    Ok(_) => {
      // Handed over, not written here: the response does not wait for it.
      ignore(deps.audit.try_push("transfer \{from} -> \{to} \{cents}"))
      let after = match find_or_none(deps.sess, from) {
        Some(w) => wallet_json(w)
        None => Json::null()
      }
      @moonapi.json(
        200,
        Json({ "moved": Json::number(cents.to_double()), "from": after }),
      )
    }
  }
}

///|
/// The wallet, as an event stream: three frames and then the end. A frame leaves
/// when it is sent, so a client sees the balance before the connection closes
/// rather than a document shaped like a stream.
///
/// A stream has answered `200` before it can find out whether the row exists, so
/// the bad news travels as a frame. That is not a compromise, it is what an event
/// stream is: the status is spent at the start.
fn handle_events(deps : Deps, ctx : @moonapi.Context) -> @moonapi.Stream {
  let id = match ctx.param("id") {
    Some(s) =>
      match parse_id(s) {
        Some(n) => n
        None => 0L
      }
    None => 0L
  }
  match find_or_none(deps.sess, id) {
    None =>
      @moonapi.sse(e => {
        e.send(@sse.Event::new(data="no such wallet", kind="gone"))
      })
    Some(w) =>
      @moonapi.sse(e => {
        e.send(@sse.Event::of("wallet \{w.id}"))
        e.send(@sse.Event::new(data=w.owner, kind="owner", id="owner"))
        e.send(
          @sse.Event::new(
            data=w.cents.to_string(),
            kind="balance",
            id="balance",
          ),
        )
      })
  }
}

///|
/// The application: a metrics endpoint the middleware fills, the ledger's routes
/// under one prefix, and the one route that is behind a token. The descriptor of
/// the two bodies is registered with the route, so the check runs before the
/// handler rather than inside it.
pub fn build_app(deps : Deps, secret : String) -> @moonapi.App {
  let app = @moonapi.App::new()
  app.describe(
    title="greet",
    summary="the greet ledger, with the parts a deployment needs",
    api_version="0.9.0",
  )
  @zero.mount_metrics(app, deps.metrics)
  let api = @zero.Group::new(app, "/api/v1")
  api.get(
    "/wallets",
    ctx => handle_list(deps, ctx),
    summary="a page of wallets",
  )
  // A body descriptor is registered on the app rather than through the group: a
  // group carries a prefix and route options, a descriptor carries a schema, and
  // the two are not the same kind of setting.
  app.post(
    "/api/v1/wallets",
    ctx => handle_create(deps, ctx),
    endpoint=@endpoint.Endpoint::new(request_body=new_wallet_body()),
    summary="open a wallet",
  )
  app.post(
    "/api/v1/transfers",
    ctx => handle_transfer(deps, ctx),
    endpoint=@endpoint.Endpoint::new(request_body=transfer_body()),
    summary="move money",
  )
  app.stream(
    "/api/v1/wallets/{id}/events",
    ctx => handle_events(deps, ctx),
    summary="a wallet, as it changes",
  )
  let admin = api.sub("/admin").options_(@zero.RouteOptions::new().jwt(secret~))
  admin.get(
    "/wallets/{id}",
    ctx => handle_one(deps, ctx),
    summary="one wallet, if the token says so",
  )
  app
}

///|
/// The service around the application: request id, recovery, and the metric set
/// the `/metrics` route reads. The token check is not here — it belongs to the
/// one route that needs it, which is why it was registered with the group.
pub fn build_server(deps : Deps, secret : String) -> @moonasgi.AsgiApp {
  let conf = @zero.ServiceConf::new(name="greet")
  let clock = @zero.Clock::new(() => 0L)
  @zero.Server::new(conf, build_app(deps, secret))
  .use_(@zero.request_id())
  .use_(@zero.recovery)
  .use_(@zero.metrics(deps.metrics, clock))
  .to_asgi()
}

///|
/// A service over an in-memory database, seeded, with a client that drives it
/// with no socket in sight. Four wallets rather than one so that a page has
/// something to leave out, and one of them near the cap so a credit can be
/// refused on purpose.
pub fn open() -> (Deps, @testing.Client) {
  let db = @sqlite.SqliteDriver::open(":memory:") catch {
    e => abort("open: " + e.to_string())
  }
  let sess = @moonorm.Session::new(db)
  migrate(sess) catch {
    e => abort("migrate: " + e.to_string())
  }
  seed(sess) catch {
    e => abort("seed: " + e.to_string())
  }
  let metrics = @zero.ServerMetrics::new() catch {
    _ => abort("the fixed metric names must register")
  }
  let audit : @zero.TaskRunner[String] = @zero.TaskRunner::new()
  let deps = { sess, metrics, audit, }
  (deps, @testing.Client::new(build_server(deps, secret())))
}

///|
/// The secret the admin group was given. In a deployment this is read from the
/// environment or a key service; here it is one string, because the chapter is
/// about where the check happens, not where the key comes from.
pub fn secret() -> String {
  "moonhelo"
}
