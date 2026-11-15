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
  "moonbitstack/moonasgi@0.11.2",
  "moonbitstack/moonapi@0.18.2",
  "moonbitstack/moonctl@0.13.0",
  "moonbitstack/moonorm@0.12.0",
  "moonbitstack/moondb@0.3.0",
  "moonbitstack/moonsqlite@0.4.0",
  "moonbitstack/mooncat@0.21.0",
  "moonbitstack/moonzero@0.15.0",
  "moonbitstack/moonrpc@0.22.2",
  "moonbitstack/moongql@0.11.0",
  "moonbitstack/moonjson@0.5.0",
  "moonbitstack/moonmuse@0.2.0",
  "moonbitstack/moonstate@0.2.0",
  "moonbitlang/async@0.22.5",
}
