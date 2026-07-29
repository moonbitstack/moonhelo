///|
/// Read greet.api and write one generated file: the moonapi scaffold when
/// `scaffold` is set, otherwise the moonorm model. All IO failures are reported
/// rather than propagated, so a bad path never aborts the whole run.
async fn gen_one(input : String, out : String, scaffold~ : Bool) -> Unit {
  try {
    let source = @fs.read_file(input).text()
    let spec = @moonctl.parse(source)
    let code = if scaffold {
      @moonctl.generate(spec)
    } else {
      @moonctl.generate_model(spec)
    }
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("gen: wrote " + out)
  } catch {
    e => println("gen: error writing " + out + ": " + e.to_string())
  }
}

///|
/// Regenerate both generated packages from greet.api using the published mctl.
/// Kept deterministic and path-fixed (run from the module root) so CI can diff the
/// result against the committed files.
async fn main {
  gen_one("greet.api", "genapi/greet_gen.mbt", scaffold=true)
  gen_one("greet.api", "genmodel/greet_model.mbt", scaffold=false)
}
