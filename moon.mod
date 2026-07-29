name = "Lfan-ke/greet"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/Lfan-ke/greet"

license = "Apache-2.0"

keywords = [ "goctl", "codegen", "end-to-end", "web", "moonbit", "example" ]

description = "The greet end-to-end slice of the moon* full-stack web suite: one .api spec flows mctl (moonctl) code generation -> moonapi routing -> moonzero assembly -> moonorm/moon-sqlite persistence -> mooncat native server, answered over the wire by a real HTTP client. The DoD-F acceptance that the whole stack boots and cooperates."

import {
  "Lfan-ke/moonasgi@0.1.0",
  "Lfan-ke/moonapi@0.6.0",
  "Lfan-ke/moonctl@0.6.0",
  "Lfan-ke/moonorm@0.6.0",
  "Lfan-ke/moondb@0.1.3",
  "Lfan-ke/moon-sqlite@0.1.3",
  "Lfan-ke/mooncat@0.6.0",
  "Lfan-ke/moonzero@0.6.0",
  "Lfan-ke/moonrpc@0.6.1",
  "moonbitlang/async@0.20.3",
}
