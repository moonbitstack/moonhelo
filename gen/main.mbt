///|
/// Run the published mctl over greet.api: write the moonorm model to genmodel/
/// (compiled, and what the running server persists through), and also run the
/// moonapi scaffold generator to prove it works. mctl 0.6.1 emits 0.10.5-safe
/// arrow-closure route registration (`app.get(path, ctx => handler(ctx))`), so
/// the scaffold type-checks; greet still hand-writes its routes because they
/// carry the real business logic (the goctl fill-in-the-logic workflow), so only
/// the model is generated into the build.
async fn main {
  try {
    let spec = @moonctl.parse(@fs.read_file("greet.api").text())
    @fs.write_file(
      "genmodel/greet_model.mbt",
      @moonctl.generate_model(spec),
      create_mode=CreateOrTruncate,
    )
    println("gen: wrote genmodel/greet_model.mbt")
    let bytes = @moonctl.generate(spec).length()
    println(
      "gen: mctl also produced a \{bytes}-byte moonapi scaffold (routes are hand-written for the business logic)",
    )
  } catch {
    e => println("gen: error: " + e.to_string())
  }
}
