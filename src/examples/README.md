# Examples

Five runnable tours of the stack, each a `moon run` away. All are native-only,
like the rest of the module: they configure a native server, and the whole
application links SQLite.

| # | Example | What it shows | Run |
|:--:|:--|:--|:--|
| 00 | [nine-in-one](00-nine-in-one/) | one greeting through nine libraries, one line each — the spec, the request, the route group, the typed route, the address, the SQL, the gRPC message, the GraphQL query, and a prompt answered by a scripted model. No socket, no database | `moon run src/examples/00-nine-in-one --target native` |
| 01 | [lifecycle](01-lifecycle/) | the three ways a long-lived thing stops: an application running its lifespan hooks in reverse, a connection drained behind a GOAWAY naming the last stream it accepted, and a graph that waits at a node and continues from its checkpoint | `moon run src/examples/01-lifecycle --target native` |
| 02 | [three-styles](02-three-styles/) | the same two routes registered three ways — as functions, as a value that answers the path, and as `#app.get` annotations the generator turns into `register(app)` — with a test that asserts all three answer the same bytes | `moon run src/examples/02-three-styles --target native` |
| 03 | [three-ways-data](03-three-ways-data/) | one table reached three ways — a model written by hand, a model generated from `#orm.table`, and a `SELECT` generated from `#sql.select` — with a test that reads the same row through all three and compares | `moon run src/examples/03-three-ways-data --target native` |
| 04 | [access-log](04-access-log/) | the assembly seam: a routed app wrapped by a moonzero Server with its logging layer, lowered to the `AsgiApp` the transport takes, with one access-log line per call — including the 404 | `moon run src/examples/04-access-log --target native` |
