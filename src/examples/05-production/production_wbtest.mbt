// One service, five proofs. Each test is about a layer that is not the handler's
// business: the descriptor, the token, the bracket, the queue, the counter.

///|
test "a page is bounded where the number arrives" {
  let db = @sqlite.SqliteDriver::open(":memory:")
  let sess = @moonorm.Session::new(db)
  migrate(sess)
  seed(sess)
  // Four rows, two at a time, in id order.
  let first = page(sess, 2, 0)
  assert_eq(first.length(), 2)
  assert_eq(first[0].id, 1L)
  assert_eq(first[1].id, 2L)
  let second = page(sess, 2, 2)
  assert_eq(second.map(w => w.id), [3L, 4L])
  // A limit the client chose is clamped, not obeyed: below the floor it is one
  // row, above the ceiling it is the ceiling.
  assert_eq(page(sess, 0, 0).length(), 1)
  assert_eq(page(sess, 10_000, 0).length(), 4)
  // An offset past the end is an empty page, not an error.
  assert_eq(page(sess, 2, 99).length(), 0)
}

///|
/// The declared body is refused before the handler is called, and the refusal
/// names the rule it broke. The row count is the proof that nothing ran.
async test "a body the descriptor refuses never reaches the handler" {
  let (deps, client) = open()
  let before = count(deps.sess)
  let short = client.post(
    "/api/v1/wallets",
    body=@utf8.encode("{\"owner\":\"a\",\"cents\":0}"),
    headers=[("content-type", "application/json")],
  )
  assert_eq(short.status, 422)
  assert_eq(short.text().contains("string_too_short"), true)
  let negative = client.post(
    "/api/v1/wallets",
    body=@utf8.encode("{\"owner\":\"ada\",\"cents\":-1}"),
    headers=[("content-type", "application/json")],
  )
  assert_eq(negative.status, 422)
  assert_eq(count(deps.sess), before)
  let ok = client.post(
    "/api/v1/wallets",
    body=@utf8.encode("{\"owner\":\"ada\",\"cents\":1}"),
    headers=[("content-type", "application/json")],
  )
  assert_eq(ok.status, 201)
  assert_eq(count(deps.sess), before + 1L)
}

///|
/// A token is what makes the route answer, and it is checked before the handler:
/// the two refusals and the acceptance are the whole middleware, seen from the
/// client's side.
async test "the admin route answers only with a token it signed" {
  let (_, client) = open()
  let bare = client.get("/api/v1/admin/wallets/1")
  assert_eq(bare.status, 401)
  assert_eq(bare.header("www-authenticate"), Some("Bearer"))
  let good = client.get("/api/v1/admin/wallets/1", headers=[
    ("authorization", "Bearer " + token()),
  ])
  assert_eq(good.status, 200)
  assert_eq(good.text().contains("\"owner\":\"ada\""), true)
  // One byte added to a signed token is not a token this service signed.
  let tampered = client.get("/api/v1/admin/wallets/1", headers=[
    ("authorization", "Bearer " + token() + "x"),
  ])
  assert_eq(tampered.status, 401)
}

///|
/// The point of the bracket: the debit runs, the credit is refused by the table's
/// CHECK, and the rollback puts the debit back. Without the transaction the first
/// statement would be a 20000 loss that no handler asked for.
async test "a refused credit takes the debit back with it" {
  let (deps, client) = open()
  let ok = client.post(
    "/api/v1/transfers",
    body=@utf8.encode("{\"from\":1,\"to\":3,\"cents\":5000}"),
    headers=[("content-type", "application/json")],
  )
  assert_eq(ok.status, 200)
  assert_eq(balances(deps.sess), "1=55000 2=90000 3=5100 4=250")
  // Bob is at the cap, so the credit is refused after the debit has run.
  let refused = client.post(
    "/api/v1/transfers",
    body=@utf8.encode("{\"from\":1,\"to\":2,\"cents\":20000}"),
    headers=[("content-type", "application/json")],
  )
  assert_eq(refused.status, 409)
  assert_eq(balances(deps.sess), "1=55000 2=90000 3=5100 4=250")
}

///|
/// Three frames, in the order they were sent, each on its own line — and the
/// metric set counts the request that produced them, under the path and status a
/// scrape would read.
async test "a stream is frames, and the scrape sees the call" {
  let (deps, client) = open()
  let stream = client.get("/api/v1/wallets/1/events")
  assert_eq(stream.status, 200)
  assert_eq(
    stream.header("content-type").unwrap().contains("text/event-stream"),
    true,
  )
  let frames = stream.text()
  assert_eq(frames.contains("data: wallet 1"), true)
  assert_eq(frames.contains("event: owner"), true)
  assert_eq(frames.contains("event: balance"), true)
  // The route that ran, counted once, by the middleware rather than the handler.
  assert_eq(
    deps.metrics.request_count("/api/v1/wallets/1/events", "GET", 200),
    1.0,
  )
  // And a scrape carries it: the same number, in the exposition format.
  let scrape = client.get("/metrics")
  assert_eq(scrape.status, 200)
  assert_eq(
    scrape
    .text()
    .contains(
      "http_server_requests_code_total{code=\"200\",method=\"GET\",path=\"/api/v1/wallets/1/events\"}",
    ),
    true,
  )
}

///|
/// The audit line is written after the response is built, by a task the request
/// does not wait for. Closing the queue is how the test knows the work is done:
/// the group joins the consumer, and then the lines are the whole story.
async test "the audit is written by the consumer, not by the request" {
  let (deps, client) = open()
  let lines : Array[String] = []
  @async.with_task_group(group => {
    ignore(group.spawn(() => deps.audit.run(line => lines.push(line))))
    let moved = client.post(
      "/api/v1/transfers",
      body=@utf8.encode("{\"from\":1,\"to\":3,\"cents\":5000}"),
      headers=[("content-type", "application/json")],
    )
    assert_eq(moved.status, 200)
    // A refused transfer is not a thing that happened, so it is not recorded.
    let refused = client.post(
      "/api/v1/transfers",
      body=@utf8.encode("{\"from\":1,\"to\":2,\"cents\":20000}"),
      headers=[("content-type", "application/json")],
    )
    assert_eq(refused.status, 409)
    deps.audit.close()
  })
  assert_eq(lines, ["transfer 1 -> 3 5000"])
}
