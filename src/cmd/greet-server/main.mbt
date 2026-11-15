///|
/// The whole service in one process: `greet.db` is opened and migrated, the REST
/// application listens on 127.0.0.1:12000, and greet.Greeter listens on 12001
/// over HTTP/2 cleartext. One task group, so a failure on either port stops the
/// process instead of leaving half a service running.
async fn main {
  @async.with_task_group(group => {
    ignore(group.spawn(() => @rpc.serve_greet_grpc(port=12001)))
    @server.serve_greet(host="127.0.0.1", port=12000, db_path="greet.db") catch {
      e => println("greet-server: " + e.to_string())
    }
  })
}
