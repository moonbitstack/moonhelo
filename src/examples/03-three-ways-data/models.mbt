// The table, described once and twice: as a struct the generator turns into a
// model, and as the SQL a statement is written in.

///|
/// A row of the `note` table. The annotations below say what the table is, so the
/// model is generated rather than maintained: `Note::model()` is in models.g.mbt.
#orm.table(name="note")
pub struct Note {
  #orm.column(primary_key=true, autoincrement=true)
  id : Int64?
  text : String
}

///|
/// A statement, with its parameters named. The generator writes `find_note` into
/// mapper.g.mbt: it binds `id`, runs the query on the driver, and reads the one
/// row into `Note`.
#sql.select("SELECT id, text FROM note WHERE id = #{id}")
declare fn find_note(db : &@moondb.Driver, id : Int64) -> Note? raise
