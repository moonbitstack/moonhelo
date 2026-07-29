name = "Lfan-ke/greet-gql"

version = "0.2.0"

license = "Apache-2.0"

description = "The GraphQL leg of the greet end-to-end slice. Separate module: moongql needs moonasgi 0.5.0, which is incompatible with the HTTP core's moonasgi 0.1.0 (mooncat/moonapi are built against 0.1.0)."

import {
  "Lfan-ke/moongql@0.6.1",
  "Lfan-ke/moonasgi@0.5.0",
  "moonbitlang/async@0.20.3",
}
