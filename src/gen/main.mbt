///|
/// Run the published mctl over spec/greet.api: write the moonorm model to
/// genmodel/ (compiled, and what the running server persists through), and also
/// run the moonapi scaffold generator to prove it works. greet still hand-writes
/// its routes because they carry the real business logic (the goctl
/// fill-in-the-logic workflow), so only the model is generated into the build.
///
/// Paths are relative to the module root, which is where `moon run` starts.
const SPEC_PATH : String = "src/spec/greet.api"

///|
/// Where the generated model is written.
const MODEL_PATH : String = "src/genmodel/greet_model.mbt"

///|
async fn main {
  try {
    let spec = @moonctl.parse(@fs.read_file(SPEC_PATH).text())
    @fs.write_file(
      MODEL_PATH,
      @moonctl.generate_model(spec),
      create_mode=CreateOrTruncate,
    )
    println("gen: wrote " + MODEL_PATH)
    let bytes = @moonctl.generate(spec).length()
    println(
      "gen: mctl also produced a " +
      bytes.to_string() +
      "-byte moonapi scaffold (routes are hand-written for the business logic)",
    )
  } catch {
    e => println("gen: error: " + e.to_string())
  }
}
