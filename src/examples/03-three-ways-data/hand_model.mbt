///|
/// The same model, written out. This is the form to reach for when a table has no
/// struct to hang annotations on — a view, a join, a table owned elsewhere — and
/// the two mappings are the whole point: nothing is inferred that you cannot read.
pub let note_by_hand : @moonorm.Model[Note] = @moonorm.Model::new(
  "note",
  [
    @moonorm.column("id", BigIntType, primary_key=true, autoincrement=true),
    @moonorm.column("text", TextType, nullable=false),
  ],
  note_from_row,
  note_to_columns,
)

///|
/// A row into the record. `id` is nullable because the database assigns it, and
/// the type says so rather than pretending every row has one.
fn note_from_row(r : @moondb.Row) -> Note raise @moondb.DbError {
  { id: Some(r.int64(0)), text: r.text(1), }
}

///|
/// The record into the columns an `INSERT` binds. A row that has not been written
/// yet carries no id, and `0` stands in for it — SQLite ignores the value for an
/// autoincrement column.
fn note_to_columns(n : Note) -> Array[(String, @moondb.Value)] {
  [("id", @moondb.Int64(n.id.unwrap_or(0L))), ("text", @moondb.Text(n.text))]
}
