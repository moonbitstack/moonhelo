///|
/// Run the published mctl over spec/greet.api and write the model the server
/// persists through into genmodel/: the `type` block as an `#orm.table` struct,
/// and its migrations. The build expands the annotations into `models.g.mbt`.
/// The moonapi scaffold mctl also writes is only measured: greet's routes are
/// written by hand, because they carry the business logic.
///
/// Paths are relative to the module root, which is where `moon run` starts.
const SPEC_PATH : String = "src/spec/greet.api"

///|
/// Where the generated model package lives.
const MODEL_DIR : String = "src/genmodel"

///|
/// The files of mctl's tree this module takes: the annotated model and the
/// migrations. The tree's own `moon.mod` and `moon.pkg` are for a project of its
/// own; this module has both already.
let taken : Array[String] = ["models.mbt", "migrate.mbt"]

///|
async fn main {
  try {
    let spec = @moonctl.parse(@fs.read_file(SPEC_PATH).text())
    for file in @moonctl.generate_orm_tree(spec) {
      let name = match file.path.rev_find("/") {
        Some(at) => file.path[at + 1:].to_owned()
        None => file.path
      }
      if !taken.contains(name) {
        continue
      }
      let path = MODEL_DIR + "/" + name
      @fs.write_file(path, file.content, create_mode=CreateOrTruncate)
      println("gen: wrote " + path)
    }
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
