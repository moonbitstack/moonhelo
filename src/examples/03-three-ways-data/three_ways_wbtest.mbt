///|
/// The three descriptions are the same table: same name, same columns in the same
/// order. If the annotated struct and the hand-written model drift, this is where
/// it shows up rather than in a query that silently reads the wrong column.
test "the two models describe one table" {
  let generated = Note::model()
  let written = note_by_hand
  assert_eq(generated.table, written.table)
  assert_eq(generated.column_names(), written.column_names())
}

///|
/// One row, three readers. The generated model reads it, the hand-written model
/// reads it, and the generated SQL statement reads it — and all three say the
/// same thing, which is what makes the choice between them a matter of taste
/// rather than of behaviour.
test "one row, three readers" {
  let db = @sqlite.SqliteDriver::open(":memory:")
  let sess = @moonorm.Session::new(db)
  sess.execute("CREATE TABLE note (id INTEGER PRIMARY KEY, text TEXT)", [])
  |> ignore
  sess.add(@moonorm.insert("note").set("text", @moondb.Text("first"))) |> ignore
  let by_model = sess.fetch_as(
    Note::model(),
    Note::model().select().eq("id", @moondb.Int(1)),
  )
  let by_hand = sess.fetch_as(
    note_by_hand,
    note_by_hand.select().eq("id", @moondb.Int(1)),
  )
  let by_sql = find_note(db, 1L)
  assert_eq(by_model.length(), 1)
  assert_eq(by_hand.length(), 1)
  assert_eq(by_model[0].text, "first")
  assert_eq(by_hand[0].text, "first")
  assert_eq(by_sql.unwrap().text, "first")
}

///|
/// A miss is a miss in all three: no row, an empty array, and `None`. The absence
/// of a row must not look like a row with defaults in it.
test "a row that is not there" {
  let db = @sqlite.SqliteDriver::open(":memory:")
  let sess = @moonorm.Session::new(db)
  sess.execute("CREATE TABLE note (id INTEGER PRIMARY KEY, text TEXT)", [])
  |> ignore
  let by_model = sess.fetch_as(
    Note::model(),
    Note::model().select().eq("id", @moondb.Int(99)),
  )
  assert_eq(by_model.length(), 0)
  assert_eq(find_note(db, 99L) is None, true)
}
