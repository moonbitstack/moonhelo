///|
/// The greet gRPC leg over the self-built h2c transport: the in-process Channel
/// client (a real TCP socket) lists the server's services via Server Reflection,
/// describes greet.Greeter, and calls SayHello, asserting the reply. This is what
/// `grpcurl list` / `describe` / call drive, over a real socket. The SayHello
/// assertion is mutation-guarded in the test below.
async test "greet rpc: reflection lists+describes and SayHello answers over h2c" {
  @async.with_task_group(g => {
    let task = g.spawn(() => @rpc.serve_greet_grpc(port=18076))
    @async.sleep(400)
    let ch = @net.Channel::connect("127.0.0.1", 18076)
    let refl_path = "/grpc.reflection.v1.ServerReflection/ServerReflectionInfo"

    // reflection: ListServices sees greet.Greeter.
    let ls = ch.server_streaming(
      refl_path,
      @moonrpc.encode_reflection_request(ListServices("*")),
    )
    let names = match @moonrpc.decode_reflection_response(ls.messages[0]) {
      ServiceList(n) => n
      _ => abort("reflection ListServices did not return a service list")
    }
    assert_eq(names.contains("greet.Greeter"), true)

    // reflection: FileContainingSymbol describes greet.Greeter.
    let fc = ch.server_streaming(
      refl_path,
      @moonrpc.encode_reflection_request(FileContainingSymbol("greet.Greeter")),
    )
    let protos = match @moonrpc.decode_reflection_response(fc.messages[0]) {
      FileDescriptors(p) => p
      _ => abort("reflection FileContainingSymbol did not return descriptors")
    }
    let described = @moonrpc.FileDescriptor::decode(protos[0])
    assert_eq(described.services[0].name, "Greeter")

    // unary SayHello over the wire.
    let reply = ch.unary("/greet.Greeter/SayHello", @rpc.hello_request("Ada"))
    assert_eq(reply.grpc_status, 0)
    let message = @rpc.parse_hello_reply(reply.messages[0]) catch {
      _ => abort("could not decode HelloReply")
    }
    assert_eq(message, "Hello, Ada")
    ch.close()
    task.cancel()
  })
}

///|
/// What the same server answers when the call is not the one it registered, and
/// when the request is empty: a method nobody serves is `UNIMPLEMENTED` (12) —
/// a status on the call, not a broken connection — and an empty `HelloRequest` is
/// a valid proto3 message, so it is greeted by name and not refused.
async test "greet rpc: an unknown method is UNIMPLEMENTED and an empty request is valid" {
  @async.with_task_group(g => {
    let task = g.spawn(() => @rpc.serve_greet_grpc(port=18077))
    @async.sleep(400)
    let ch = @net.Channel::connect("127.0.0.1", 18077)

    let missing = ch.unary("/greet.Greeter/Shout", @rpc.hello_request("Ada"))
    assert_eq(missing.grpc_status, 12)

    // The connection is still usable after the refused call: one status does not
    // take the stream multiplexing down with it.
    let empty = ch.unary("/greet.Greeter/SayHello", b"")
    assert_eq(empty.grpc_status, 0)
    assert_eq(
      @rpc.parse_hello_reply(empty.messages[0]) catch {
        _ => abort("could not decode HelloReply")
      },
      "Hello, ",
    )
    ch.close()
    task.cancel()
  })
}
