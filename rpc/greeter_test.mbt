///|
/// The greet gRPC leg over the self-built h2c transport: the in-process Channel
/// client (a real TCP socket) lists the server's services via Server Reflection,
/// describes greet.Greeter, and calls SayHello, asserting the reply. This is what
/// `grpcurl list` / `describe` / call drive, over a real socket. The SayHello
/// assertion is mutation-guarded in the test below.
async test "greet rpc: reflection lists+describes and SayHello answers over h2c" {
  @async.with_task_group(g => {
    let task = g.spawn(() => serve_greet_grpc(port=18076))
    @async.sleep(400)
    let ch = @net.Channel::connect("127.0.0.1", 18076)
    let refl_path = "/grpc.reflection.v1.ServerReflection/ServerReflectionInfo"

    // reflection: ListServices sees greet.Greeter.
    let ls = ch.server_streaming(
      refl_path,
      @moonrpc.encode_reflection_request(@moonrpc.ListServices("*")),
    )
    let names = match @moonrpc.decode_reflection_response(ls.messages[0]) {
      ServiceList(n) => n
      _ => abort("reflection ListServices did not return a service list")
    }
    assert_eq(names.contains("greet.Greeter"), true)

    // reflection: FileContainingSymbol describes greet.Greeter.
    let fc = ch.server_streaming(
      refl_path,
      @moonrpc.encode_reflection_request(
        @moonrpc.FileContainingSymbol("greet.Greeter"),
      ),
    )
    let protos = match @moonrpc.decode_reflection_response(fc.messages[0]) {
      FileDescriptors(p) => p
      _ => abort("reflection FileContainingSymbol did not return descriptors")
    }
    let described = @moonrpc.FileDescriptor::decode(protos[0])
    assert_eq(described.services[0].name, "Greeter")

    // unary SayHello over the wire.
    let reply = ch.unary("/greet.Greeter/SayHello", hello_request("Ada"))
    assert_eq(reply.grpc_status, 0)
    let message = parse_hello_reply(reply.messages[0]) catch {
      _ => abort("could not decode HelloReply")
    }
    assert_eq(message, "Hello, Ada")
    ch.close()
    task.cancel()
  })
}
