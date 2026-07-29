///|
/// The `HelloRequest { string name = 1 }` wire bytes for `name`.
pub fn hello_request(name : String) -> Bytes {
  let w = @moonrpc.PbWriter::new()
  w.string_(1, name)
  w.to_bytes()
}

///|
/// Read `name` (field 1) out of a `HelloRequest`.
pub fn parse_hello_request(body : Bytes) -> String raise @moonrpc.PbError {
  let r = @moonrpc.PbReader::new(body)
  let mut name = ""
  while !r.eof() {
    match r.read_tag() {
      (1, @moonrpc.LengthDelim) => name = r.read_string()
      (_, w) => r.skip(w)
    }
  }
  name
}

///|
/// The `HelloReply { string message = 1 }` wire bytes for `message`.
pub fn hello_reply(message : String) -> Bytes {
  let w = @moonrpc.PbWriter::new()
  w.string_(1, message)
  w.to_bytes()
}

///|
/// Read `message` (field 1) out of a `HelloReply`.
pub fn parse_hello_reply(body : Bytes) -> String raise @moonrpc.PbError {
  let r = @moonrpc.PbReader::new(body)
  let mut message = ""
  while !r.eof() {
    match r.read_tag() {
      (1, @moonrpc.LengthDelim) => message = r.read_string()
      (_, w) => r.skip(w)
    }
  }
  message
}

///|
/// The greet.Greeter/SayHello handler: greet the request's name. A malformed
/// request decodes to an empty name and still gets a reply.
fn say_hello(request : Bytes) -> Bytes {
  let name = parse_hello_request(request) catch { _ => "" }
  hello_reply("Hello, " + name)
}

///|
/// The `greet.proto` descriptor, registered with reflection so a client can
/// discover greet.Greeter and its messages over the wire.
fn greet_descriptor() -> @moonrpc.FileDescriptor {
  @moonrpc.FileDescriptor::new(
    "greet.proto",
    "greet",
    messages=[
      @moonrpc.MessageDescriptor::{
        name: "HelloRequest",
        fields: [
          @moonrpc.FieldDescriptor::scalar("name", 1, @moonrpc.TypeString),
        ],
      },
      @moonrpc.MessageDescriptor::{
        name: "HelloReply",
        fields: [
          @moonrpc.FieldDescriptor::scalar("message", 1, @moonrpc.TypeString),
        ],
      },
    ],
    services=[
      @moonrpc.ServiceDescriptor::{
        name: "Greeter",
        methods: [
          @moonrpc.MethodDescriptor::{
            name: "SayHello",
            input_type: ".greet.HelloRequest",
            output_type: ".greet.HelloReply",
            client_streaming: false,
            server_streaming: false,
          },
        ],
      },
    ],
  )
}

///|
/// Serve greet.Greeter over h2c with Server Reflection registered, blocking in
/// the accept loop until the running task is cancelled.
pub async fn serve_greet_grpc(
  host? : String = "127.0.0.1",
  port? : Int = 50051,
) -> Unit {
  let server = @net.GrpcServer::new()
  server.register("/greet.Greeter/SayHello", say_hello)
  let refl = @moonrpc.ReflectionService::new()
  refl.add_file(greet_descriptor())
  server.register_reflection(refl)
  server.serve(host~, port~)
}
