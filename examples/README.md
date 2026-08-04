# greet examples

- **00-nine-in-one** — the whole moon* suite in one breath. A single greeting for
  `heke1228` is carried through all nine libraries, one line each: moonctl parses the
  `.api` spec, moonasgi frames the request, moonzero mounts the route group on moonapi
  which answers it, mooncat names the address it would bind, moonorm renders the SQL
  that persists it, moonrpc packs it into a gRPC DATA frame, moongql serves it as a
  GraphQL field, and moonkoog builds the agent prompt that speaks it. In-process, no
  socket, no database.

  ```
  moon run examples/00-nine-in-one --target native
  ```
