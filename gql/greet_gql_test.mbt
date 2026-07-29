///|
/// The greet GraphQL leg over the wire: a real async HTTP client POSTs a query to
/// /graphql and gets back the exact `{ data: { greeting } }` JSON. The greeting
/// text is mutation-guarded (break the resolver -> this assertion goes red).
async test "greet gql: a real HTTP POST to /graphql returns the greeting" {
  @async.with_task_group(g => {
    let task = g.spawn(() => serve_greet_gql(port=18090))
    @async.sleep(400)
    let (resp, body) = @http.post(
      "http://127.0.0.1:18090/graphql", "{\"query\":\"{ greeting(name: \\\"Ada\\\") }\"}",
    )
    assert_eq(resp.code, 200)
    assert_eq(body.json(), { "data": { "greeting": "Hello, Ada" } })
    task.cancel()
  })
}
