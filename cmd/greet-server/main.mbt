///|
/// Open (or create) greet.db, run the migration, and serve greet on
/// 127.0.0.1:8080 until the process is killed.
async fn main {
  @server.serve_greet(host="127.0.0.1", port=12000, db_path="greet.db") catch {
    e => println("greet-server: " + e.to_string())
  }
}
