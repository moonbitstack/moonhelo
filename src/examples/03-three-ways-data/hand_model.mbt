///|
/// The same model, written out. This is the form to reach for when a table has no
/// struct to hang annotations on — a view, a join, a table owned elsewhere — and
/// the closures are the whole point: nothing is inferred that you cannot read.
pub let note_by_hand : @moonorm.Model[Note] = @moonorm.Model::new(
  "note",
  [
    @moonorm.column("id", BigIntType, primary_key=true, autoincrement=true),
    @moonorm.column("text", TextType, nullable=false),
  ],
  r => { id: Some(r.int64(0)), text: r.text(1), },
  n => {
    [("id", @moondb.Int64(n.id.unwrap_or(0L))), ("text", @moondb.Text(n.text))]
  },
)
