name = "Lfan-ke/greet"

version = "0.6.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonhelo"

license = "Apache-2.0"

keywords = [ "goctl", "codegen", "end-to-end", "web", "moonbit", "example" ]

description = "The greet end-to-end slice of the moon* full-stack web suite: one .api spec flows mctl (moonctl) code generation -> moonapi routing -> moonzero assembly -> moonorm/moon-sqlite persistence -> mooncat native server, answered over the wire by a real HTTP client. The DoD-F acceptance that the whole stack boots and cooperates."

import {
  "moonbitstack/moonasgi@0.10.0",
  "moonbitstack/moonapi@0.11.0",
  "moonbitstack/moonctl@0.8.0",
  "moonbitstack/moonorm@0.9.0",
  "moonbitstack/moondb@0.1.8",
  "moonbitstack/moonsqlite@0.3.0",
  "moonbitstack/mooncat@0.9.0",
  "moonbitstack/moonzero@0.8.0",
  "moonbitstack/moonrpc@0.13.0",
  "moonbitstack/moongql@0.9.0",
  "moonbitlang/async@0.20.3",
  "DC-Z-lab/moonllm@0.1.0",
  "moonbitstack/moonkoog@0.5.0",
}
