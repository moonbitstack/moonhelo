// Everything in this chapter in one run: a page, a refused body, a refused token,
// a transfer the ledger takes and one it does not, a stream, and a scrape.
//
//     moon run src/examples/05-production --target native

///|
async fn main {
  let (deps, client) = open()
  let lines : Array[String] = []
  @async.with_task_group(group => {
    // One consumer, in its own task: the request hands the line over and returns.
    ignore(group.spawn(() => deps.audit.run(line => lines.push(line))))
    let page_resp = client.get("/api/v1/wallets?limit=2&offset=1")
    println(
      "page         -> \{page_resp.status} " + page_line(page_resp.text()),
    )
    let created = client.post(
      "/api/v1/wallets",
      body=@utf8.encode("{\"owner\":\"eve\",\"cents\":0}"),
      headers=[("content-type", "application/json")],
    )
    println("create       -> \{created.status} \{created.text()}")
    let short = client.post(
      "/api/v1/wallets",
      body=@utf8.encode("{\"owner\":\"e\",\"cents\":0}"),
      headers=[("content-type", "application/json")],
    )
    println("create/short -> \{short.status} \{errors_of(short.text())}")
    let bare = client.get("/api/v1/admin/wallets/1")
    println("admin/none   -> \{bare.status} \{bare.text()}")
    let tokened = client.get("/api/v1/admin/wallets/1", headers=[
      ("authorization", "Bearer " + token()),
    ])
    println("admin/token  -> \{tokened.status} \{tokened.text()}")
    let moved = client.post(
      "/api/v1/transfers",
      body=@utf8.encode("{\"from\":1,\"to\":3,\"cents\":5000}"),
      headers=[("content-type", "application/json")],
    )
    println("move         -> \{moved.status} \{moved.text()}")
    // Bob's wallet is already at the cap, so the credit is refused after the
    // debit has run. What the balances say next is the rollback.
    let refused = client.post(
      "/api/v1/transfers",
      body=@utf8.encode("{\"from\":1,\"to\":2,\"cents\":20000}"),
      headers=[("content-type", "application/json")],
    )
    println("move/cap     -> \{refused.status} \{refused.text()}")
    println("balances     -> " + balances(deps.sess))
    let events = client.get("/api/v1/wallets/1/events")
    println("events       -> \{events.status} " + frames(events.text()))
    let scrape = client.get("/metrics")
    println(
      "metrics      -> \{scrape.status} http_server_requests_code " +
      deps.metrics.request_count("/api/v1/wallets", "GET", 200).to_string(),
    )
    deps.audit.close()
  })
  println("--- audit, written by the other task ---")
  for line in lines {
    println(line)
  }
}

///|
/// A token that lives a long time, signed with the secret the group was given. The
/// claims are the service's own; the middleware only asks whether the signature
/// holds and the clock is inside `exp`.
fn token() -> String {
  let claims : Map[String, Json] = Map([
    ("sub", Json::string("ada")),
    ("exp", Json::number(4102444800.0)),
  ])
  @zero.jwt_sign(claims, secret())
}

///|
fn seed(sess : @moonorm.Session) -> Unit raise @moondb.DbError {
  let rows = [("ada", 60000L), ("bob", 90000L), ("cy", 100L), ("dee", 250L)]
  for row in rows {
    sess.execute("INSERT INTO wallet (owner, cents) VALUES (?, ?)", [
      @moondb.Text(row.0),
      @moondb.Int64(row.1),
    ])
    |> ignore
  }
}

///|
/// The balances, read back after the refused transfer: `from` is where it was, so
/// the debit that ran before the failure is not in the table either.
fn balances(sess : @moonorm.Session) -> String {
  let mut out = ""
  for id in [1L, 2L, 3L, 4L] {
    let cents = match find_or_none(sess, id) {
      Some(w) => w.cents.to_string()
      None => "-"
    }
    out = out + (if out == "" { "" } else { " " }) + "\{id}=\{cents}"
  }
  out
}

///|
/// A 422 body is a list of violations; this prints the first one's type, which is
/// the pydantic name for what the descriptor refused.
fn errors_of(text : String) -> String {
  let parsed = try @moonjson.loads(text, @moonjson.strict) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
  match parsed {
    Some(Json::Object(m)) =>
      match m.get("detail") {
        Some(Json::Array(items)) =>
          match items {
            [Json::Object(first), ..] =>
              match first.get("type") {
                Some(Json::String(t)) => t
                _ => "detail"
              }
            _ => "detail"
          }
        _ => "detail"
      }
    _ => "detail"
  }
}

///|
/// The frames of an event stream, one per line on the wire, read as one line here
/// — the first three, which is how far a reader needs to look to see the shape.
fn frames(text : String) -> String {
  let parts : Array[String] = []
  for line in text.split("\n") {
    if line.length() > 0 && parts.length() < 5 {
      parts.push(line.to_owned())
    }
  }
  parts.join(" · ")
}

///|
/// A page, said in one line: how many rows came back, how many there are, and
/// where the next page starts. The body itself is a JSON document; the transcript
/// is for reading.
fn page_line(text : String) -> String {
  let parsed = try @moonjson.loads(text, @moonjson.strict) catch {
    _ => return text
  } noraise {
    v => Some(v)
  }
  match parsed {
    Some(Json::Object(m)) => {
      let on_page = match m.get("items") {
        Some(Json::Array(items)) => items.length().to_string()
        _ => "?"
      }
      let total = match m.get("total") {
        Some(Json::Number(n, ..)) => n.to_string()
        _ => "?"
      }
      let next = match m.get("next") {
        Some(Json::Number(n, ..)) => n.to_string()
        Some(Json::Null) => "none"
        _ => "?"
      }
      on_page + " of " + total + ", next " + next
    }
    _ => text
  }
}
