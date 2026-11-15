///|
/// Both models hand back `Array[Note]`; this prints what a reader wants to see —
/// whether the row came back at all, and what it says.
fn text_of(rows : Array[Note]) -> String {
  if rows.length() == 0 {
    return "no row"
  }
  let id = match rows[0].id {
    Some(i) => i.to_string()
    None => "-"
  }
  id + " " + rows[0].text
}
