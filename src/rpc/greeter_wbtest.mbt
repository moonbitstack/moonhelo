///|
/// The two messages round-trip through the protobuf wire format, and a field this
/// side does not know is skipped rather than ending the read: that is what lets a
/// peer add a field without breaking an older reader.
test "hello messages round-trip" {
  assert_eq(parse_hello_request(hello_request("Ada")), "Ada")
  assert_eq(parse_hello_request(hello_request("")), "")
  assert_eq(parse_hello_reply(hello_reply("Hello, Ada")), "Hello, Ada")

  // An empty message is a valid one: every field is optional in proto3.
  assert_eq(parse_hello_request(b""), "")

  // Field 2 is not HelloRequest's, and it does not disturb field 1.
  let w = @moonrpc.PbWriter::new()
  w.int32(2, 7)
  w.string_(1, "Ada")
  assert_eq(parse_hello_request(w.to_bytes()), "Ada")
}

///|
/// The handler answers a request it cannot read with an empty name rather than
/// failing the call, and greets the name it can read: the greeting prefix is the
/// same one the end-to-end test asserts over a socket.
test "say_hello greets what it can read" {
  assert_eq(parse_hello_reply(say_hello(hello_request("Ada"))), "Hello, Ada")
  assert_eq(parse_hello_reply(say_hello(b"")), "Hello, ")
  assert_eq(parse_hello_reply(say_hello(b"\xff")), "Hello, ")
}
