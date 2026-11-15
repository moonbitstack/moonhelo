///|
/// One row written once, read three ways.
///
///     moon run src/examples/03-three-ways-data --target native
fn main raise {
  let db = @sqlite.SqliteDriver::open(":memory:")
  let sess = @moonorm.Session::new(db)
  sess.execute("CREATE TABLE note (id INTEGER PRIMARY KEY, text TEXT)", [])
  |> ignore
  sess.add(@moonorm.insert("note").set("text", @moondb.Text("first"))) |> ignore
  let generated = sess.fetch_as(
    Note::model(),
    Note::model().select().eq("id", @moondb.Int(1)),
  )
  let written = sess.fetch_as(
    note_by_hand,
    note_by_hand.select().eq("id", @moondb.Int(1)),
  )
  let mapped = find_note(db, 1L)
  println("generated model : " + text_of(generated))
  println("written model   : " + text_of(written))
  println("generated SQL   : " + mapped.map(n => n.text).unwrap_or("none"))
}
