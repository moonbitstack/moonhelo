///|
/// Starting and stopping, across the suite. Every long-lived thing in moon* can now
/// be shut down without cutting anyone off, and each layer spells that differently:
/// an app runs lifespan hooks, a gRPC connection is drained behind a GOAWAY naming
/// the last stream it accepted, and an agent stops between nodes so a tool call in
/// flight always finishes. All three run in-process here, no socket.
///
///     moon run examples/01-lifecycle --target native
#coverage.skip
async fn main {
  let log : Array[String] = []

  // moonapi: startup hooks run in registration order and shutdown in reverse, so a
  // resource is released before whatever it was opened from.
  let app = @moonapi.App::new()
  app.get("/greet", _ctx => @moonapi.text(200, "Bonjour, heke1228!"))
  app.on_startup(() => log.push("open db"))
  app.on_startup(() => log.push("warm cache"))
  app.on_shutdown(() => log.push("drop cache"))
  app.on_shutdown(() => log.push("close db"))
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  let replies = @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
    @moonasgi.Event::LifespanStartup,
    @moonasgi.Event::LifespanShutdown,
  ])
  println("moonapi : " + log.join(" -> "))
  println(
    "moonapi : " +
    replies.length().to_string() +
    " lifespan replies, both complete",
  )

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

  // moonkoog: the run is asked to stop mid-graph. The node it is in finishes, the one
  // after it never starts, and the text reached so far comes back on AgentStopped.
  let client = @agent.MockClient::new([
    @prompt.Message::assistant("Bonjour, heke1228!"),
  ])
  let agent = @agent.AIAgent::new(client, model=@llm.deepseek_v4_flash)
  let handle = @agent.RunHandle::new()
  let visited : Array[String] = []
  let strategy = @agent.AIAgentStrategy::new("lifecycle")
    .custom_node("halt", (_session, _v) => {
      visited.push("halt")
      handle.stop()
      @agent.VText("stopped mid-run")
    })
    .custom_node("after", (_session, v) => {
      visited.push("after")
      v
    })
    .edge(@agent.start_node, "halt")
    .edge("halt", "after")
    .edge("after", @agent.finish_node)
  let outcome = agent.run_strategy(strategy, "greet heke1228", stop=handle) catch {
    @agent.AgentStopped(partial) => partial
    _ => "unexpected error"
  }
  println("moonkoog: " + outcome + " (ran: " + visited.join(", ") + ")")
}
