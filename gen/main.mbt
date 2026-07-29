///|
/// Run the published mctl over greet.api: write the moonorm model to genmodel/
/// (compiled, and what the running server persists through), and also run the
/// moonapi scaffold generator to prove it works. The scaffold is not compiled
/// here: the published moonctl targets a pre-0.10.5 compiler where a pure named
/// handler coerces to the raising `ApiHandler`; under moonc 0.10.5 that coercion
/// is gone, so its `app.get(path, handler)` stubs no longer type-check. greet
/// hand-writes the routes instead (the goctl fill-in-the-logic workflow), so only
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
    let scaffold = @moonctl.generate(spec)
    println(
      "gen: mctl also produced a " +
      scaffold.length().to_string() +
      "-byte moonapi scaffold (not compiled under moonc 0.10.5; routes are hand-written)",
    )
  } catch {
    e => println("gen: error: " + e.to_string())
  }
}
