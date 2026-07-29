///|
/// The greet GraphQL schema: `type Query { greeting(name: String!): String! }`.
fn gql_schema() -> @gql.Schema {
  let schema = @gql.Schema::new()
  let query = schema.object("Query")
  query.field_args(
    "greeting",
    [("name", @gql.NonNull(@gql.Scalar("String")))],
    @gql.NonNull(@gql.Scalar("String")),
  )
  schema
}

///|
/// The greet resolvers: `Query.greeting` greets its `name` argument.
fn gql_resolvers() -> @gql.Resolvers {
  let resolvers = @gql.Resolvers::new()
  resolvers.field("Query", "greeting", info => {
    let name = match info.arg("name") {
      String(s) => s
      _ => ""
    }
    ("Hello, " + name).to_json()
  })
  resolvers
}

///|
/// The moongql request handler for the greet schema: `(Request) -> Response`,
/// executing a query on `POST /graphql` and serving GraphiQL on `GET`. Mounted as
/// a route on the same moonapi app mooncat serves, so GraphQL rides the shared
/// moonasgi transport rather than a second HTTP server.
fn gql_handler() -> @moonasgi.Handler {
  @gql.graphql_handler(gql_schema(), gql_resolvers())
}
