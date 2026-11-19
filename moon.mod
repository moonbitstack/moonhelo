name = "moonbitstack/moonhelo"

version = "0.6.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonhelo"

license = "Apache-2.0"

keywords = [
  "example",
  "end-to-end",
  "full-stack",
  "web",
  "codegen",
  "goctl",
  "moonapi",
  "moonasgi",
  "moonzero",
  "moonorm",
  "mooncat",
  "moonrpc",
  "moongql",
  "moonmuse",
  "moonstate",
  "sqlite",
  "grpc",
  "graphql",
  "openapi",
  "rest",
  "http",
  "moonbit",
]

description = "The end-to-end greet slice of the MoonBit backend stack: one .api spec is generated into a moonorm model by moonctl, routed by moonapi, assembled by moonzero, persisted through moonorm and moonsqlite, answered by mooncat, and described over gRPC and GraphQL from the same module. An example application, not a library."

source = "src"

import {
  "moonbitstack/moonasgi@0.11.3",
  "moonbitstack/moonapi@0.18.3",
  "moonbitstack/moonctl@0.13.2",
  "moonbitstack/moonorm@0.12.1",
  "moonbitstack/moondb@0.3.1",
  "moonbitstack/moonsqlite@0.4.1",
  "moonbitstack/mooncat@0.21.1",
  "moonbitstack/moonzero@0.15.1",
  "moonbitstack/moonrpc@0.22.3",
  "moonbitstack/moongql@0.11.1",
  "moonbitstack/moonhttp@0.16.1",
  "moonbitstack/moonjson@0.5.1",
  "moonbitstack/moonmuse@0.2.1",
  "moonbitstack/moonfetch@0.2.1",
  "moonbitstack/moonmcp@0.2.2",
  "moonbitstack/moonstate@0.2.2",
  "moonbitlang/async@0.22.5",
}

rule(
  name: "orm",
  command: "moonx moonbitstack/moonorm/cmd/orm@0.12.1 -C \"$mod_dir\" \"$input\" -o \"$output\"",
)

rule(
  name: "sql",
  command: "moonx moonbitstack/moonorm/cmd/sql@0.12.1 -C \"$mod_dir\" \"$input\" -o \"$output\"",
)

rule(
  name: "routes",
  command: "moonx moonbitstack/moonapi/cmd/routes@0.18.3 -C \"$mod_dir\" \"$input\" -o \"$output\"",
)
