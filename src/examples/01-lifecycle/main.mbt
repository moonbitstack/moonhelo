///|
/// Starting and stopping, across the suite. Every long-lived thing here can be
/// shut down without cutting anyone off, and each layer spells that differently:
/// an app runs lifespan hooks, a gRPC connection is drained behind a GOAWAY
/// naming the last stream it accepted, and a graph stops between two nodes and
/// continues from its checkpoint once the answer arrives. All three run
/// in-process: no socket.
///
///     moon run src/examples/01-lifecycle --target native
#coverage.skip
async fn main {
  let log : Array[String] = []

  // moonapi: startup hooks run in registration order and shutdown in reverse, so a
  // resource is released before whatever it was opened from. The test client drives
  // the ASGI lifespan around the work, which is what a server does at boot.
  let app = @moonapi.App::new()
  app.get("/greet", _ctx => @moonapi.text(200, "Bonjour, heke1228!"))
  app.on_startup(_state => log.push("open db"))
  app.on_startup(_state => log.push("warm cache"))
  app.on_shutdown(_state => log.push("drop cache"))
  app.on_shutdown(_state => log.push("close db"))
  let client = @testing.Client::new(app.to_asgi())
  let started = client.lifespan(() => log.join(" -> "))
  println("moonapi : " + started)
  println("moonapi : " + log.join(" -> "))

  // moonrpc: a drained connection announces the last stream it accepted, so a client
  // knows what was processed and what is safe to re-issue somewhere else.
  let server = @moonrpc.H2Server::new()
  server.register("/greet.Greeter/SayHello", req => req)
  let frames = server.goaway(server.highest_stream())
  println(
    "moonrpc : " +
    frames.length().to_string() +
    " GOAWAY frame naming stream " +
    server.highest_stream().to_string() +
    ", " +
    server.active_streams().to_string() +
    " calls still running",
  )

  // moonstate: the run is asked a question it cannot answer yet, so it stops at
  // that node and keeps everything written so far in its checkpoint. The answer
  // resumes the same thread: the node reads it and the run finishes. One graph,
  // one saver, two calls — a second graph would not see the checkpoint.
  let graph = greet_graph()
  let thread = "greet-lifecycle"
  let stopped = try {
    ignore(graph.run({ text: None, }, thread~))
    "finished without stopping"
  } catch {
    @moonstate.GraphError::Interrupted(value~, ..) => value.stringify()
    _ => "the run failed for another reason"
  }
  println("moonstate: stopped, asking " + stopped)
  let done = graph.resume_with(thread, Json("release it"))
  println("moonstate: resumed -> " + done.lines.join(" -> "))
}

///|
/// What a run carries: every line a node wrote, in the order they were merged.
#derive(@json.ToJson, @json.FromJson)
struct Ledger {
  lines : Array[String]
}

///|
/// What one node writes. `None` is a write that carries no line, which is how a
/// run starts: a node touches only what it has something to say about.
#derive(@json.ToJson, @json.FromJson)
struct Line {
  text : String?
}

///|
/// Folding a write into the state: a node touches only its own field, so two
/// nodes in one superstep merge without knowing about each other.
fn merge_line(ledger : Ledger, line : Line) -> Ledger {
  match line.text {
    Some(text) => { lines: ledger.lines + [text], }
    None => ledger
  }
}

///|
/// A two-node graph: `open` writes, `confirm` asks once and writes the answer on
/// the second visit. The saver is what makes the second visit possible.
fn greet_graph() -> @moonstate.Graph[Ledger, Line] raise {
  @moonstate.Builder::new(merge=merge_line, initial={ lines: [], })
  .entry("open")
  .node("open", (_state, _run) => [@moonstate.Write({ text: Some("open db"), })])
  .node("confirm", (_state, run) => {
    match run.answer() {
      Some(answer) =>
        [@moonstate.Write({ text: Some("confirmed " + answer.stringify()), })]
      None => [@moonstate.Interrupt(Json("release the greeting?"))]
    }
  })
  .edge("open", "confirm")
  .compile("lifecycle", saver=@moonstate.MemorySaver::new())
}
