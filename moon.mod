name = "Lfan-ke/greet"

version = "0.6.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonhelo"

license = "Apache-2.0"

keywords = [ "goctl", "codegen", "end-to-end", "web", "moonbit", "example" ]

description = "The greet end-to-end slice of the moon* full-stack web suite: one .api spec flows mctl (moonctl) code generation -> moonapi routing -> moonzero assembly -> moonorm/moon-sqlite persistence -> mooncat native server, answered over the wire by a real HTTP client. The DoD-F acceptance that the whole stack boots and cooperates."

import {
  "moonbitstack/moonasgi@0.10.0",
  "moonbitstack/moonapi@0.12.0",
  "moonbitstack/moonctl@0.10.0",
  "moonbitstack/moonorm@0.10.0",
  "moonbitstack/moondb@0.2.0",
  "moonbitstack/moonsqlite@0.3.1",
  "moonbitstack/mooncat@0.14.4",
  "moonbitstack/moonzero@0.11.2",
  "moonbitstack/moonrpc@0.19.2",
  "moonbitstack/moongql@0.9.0",
  "moonbitlang/async@0.20.3",
  "DC-Z-lab/moonllm@0.1.0",
  "moonbitstack/moonkoog@0.6.1",
}
