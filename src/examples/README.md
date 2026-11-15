# Examples

Two runnable tours of the stack, each a `moon run` away. Both are native-only,
like the rest of the module: they configure a native server, and the whole
application links SQLite.

| # | Example | What it shows | Run |
|:--:|:--|:--|:--|
| 00 | [nine-in-one](00-nine-in-one/) | one greeting through nine libraries, one line each — the spec, the request, the route group, the typed route, the address, the SQL, the gRPC message, the GraphQL query, and a prompt answered by a scripted model. No socket, no database | `moon run src/examples/00-nine-in-one --target native` |
| 01 | [lifecycle](01-lifecycle/) | the three ways a long-lived thing stops: an application running its lifespan hooks in reverse, a connection drained behind a GOAWAY naming the last stream it accepted, and a graph that waits at a node and continues from its checkpoint | `moon run src/examples/01-lifecycle --target native` |
