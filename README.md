<div align="center">

# greet

**The end-to-end slice of the moon\* full-stack web suite.**

[![Check and Test](https://github.com/Lfan-ke/greet/actions/workflows/ci.yml/badge.svg)](https://github.com/Lfan-ke/greet/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

</div>

`greet` is the acceptance test for the whole moon\* stack: one `.api` spec flows
through code generation, framework, assembly, ORM, and server, and a real HTTP
client hits the result over the wire. If this repo's CI is green, the pieces boot
and cooperate — that is the point of it.

```mermaid
flowchart LR
  api["greet.api"] -->|mctl gen| model["moonorm model<br/>(genmodel)"]
  model --> app["moonapi App<br/>+ hand-written routes"]
  app -->|moonzero assemble<br/>+ middleware| asgi["AsgiApp"]
  asgi -->|mooncat serve| http["native HTTP"]
  http -->|curl / async @http| client["real client"]
  model -.->|Session| sqlite[("SQLite<br/>moon-sqlite")]
```

## The chain

| stage | repo | what it does here |
|-------|------|-------------------|
| spec | — | `greet.api`: a `service` with `/ping`, `POST /users`, `GET /users/:id`, and a `type User` |
| generate | [moonctl](https://github.com/Lfan-ke/moonctl) (`mctl`) | `genmodel/`: the `User` model, columns, Row decoder, and migration |
| framework | [moonapi](https://github.com/Lfan-ke/moonapi) | routing, the OpenAPI document, the request-id middleware |
| assembly | [moonzero](https://github.com/Lfan-ke/moonzero) | wraps the app with go-zero-style request logging |
| ORM | [moonorm](https://github.com/Lfan-ke/moonorm) + [moondb](https://github.com/Lfan-ke/moondb) | the `Session` that persists and reads users |
| driver | [moon-sqlite](https://github.com/Lfan-ke/moon-sqlite) | a real SQLite file behind the Session |
| server | [mooncat](https://github.com/Lfan-ke/mooncat) | serves the assembled app over native HTTP |
| SEAM | [moonasgi](https://github.com/Lfan-ke/moonasgi) | the Scope/Receive/Send contract every layer shares |
| gRPC | [moonrpc](https://github.com/Lfan-ke/moonrpc) | serves greet.Greeter over h2c with Server Reflection (`rpc/`) |
| GraphQL | [moongql](https://github.com/Lfan-ke/moongql) | serves `Query.greeting` at `/graphql`, mounted on the same mooncat server |

Routes are hand-written — the ordinary goctl workflow, where generated
scaffolding is the starting point and the business logic is filled in — but the
generated `User` model stays the persistence layer, so a request still
round-trips through the exact model the spec produced.

mctl also generates a moonapi route scaffold (`@moonctl.generate`), and `gen`
runs it. `moonctl@0.6.1` emits 0.10.5-safe arrow-closure registration
(`app.get(path, ctx => handler(ctx))`), so the scaffold type-checks; greet still
writes its routes by hand because they carry the real business logic — the
ordinary goctl workflow where the scaffold is the starting point and the logic is
filled in.

## gRPC leg

`greet.proto` defines `Greeter.SayHello(HelloRequest) -> HelloReply`. `rpc/`
serves it over moonrpc's self-built HTTP/2 (h2c) transport with `grpc.reflection.v1`
Server Reflection registered. The test drives it the way `grpcurl` does — over a
real `@socket.Tcp`, through the in-process `Channel` client: `ListServices` sees
`greet.Greeter`, `FileContainingSymbol` returns its `FileDescriptorProto`, and a
unary `SayHello("Ada")` answers `"Hello, Ada"`.

## GraphQL leg

`server/gql.mbt` defines `type Query { greeting(name: String!): String! }` and
mounts moongql's handler as `GET`/`POST /graphql` on the same moonapi app mooncat
serves. The end-to-end test POSTs `{ greeting(name: "Ada") }` to that one server
and asserts the exact `{"data":{"greeting":"Hello, Ada"}}` — GraphQL rides the
shared moonasgi transport alongside the REST routes, not a second HTTP server.

This used to be a separate module: moongql pinned `moonasgi@0.5.0` while the HTTP
core pinned `moonasgi@0.1.0`, and one module resolves a single moonasgi for all
its packages. Aligning the whole suite on `moonasgi@0.6.1` removed the skew, so
the leg folds back into the main module and the same server answers REST,
OpenAPI, and GraphQL on one port.

## Run it

```console
$ moon run --target native gen           # regenerate genmodel/ from greet.api
$ moon test --target native              # in-process end-to-end: real @http client over a live socket
$ moon run --target native cmd/greet-server &
$ curl -s localhost:8080/ping            # -> pong
$ curl -s -XPOST localhost:8080/users -d '{"name":"Ada"}'
{"id":1,"name":"Ada"}
$ curl -s localhost:8080/users/1         # -> {"id":1,"name":"Ada"}
$ curl -s localhost:8080/openapi.json    # -> the OpenAPI document
$ curl -s -XPOST localhost:8080/graphql -d '{"query":"{ greeting(name: \"Ada\") }"}'
{"data":{"greeting":"Hello, Ada"}}
```

## Layout

- `greet.api` — the spec.
- `gen/` — runs mctl over the spec and writes the generated model.
- `genmodel/` — mctl output, committed so the diff is visible and regenerated in
  CI so it stays honest.
- `server/` — the assembled service and the end-to-end test.
- `cmd/greet-server/` — the binary CI runs and curls.

## License

Apache-2.0.
