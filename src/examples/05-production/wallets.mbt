// Ten lines of SQL and the two rules a ledger cannot do without. Everything the
// chapter adds happens around these statements, so they stay deliberately plain.

///|
/// A wallet: an owner and a balance in cents. Money is an integer here because a
/// cent is a unit and a double is not.
pub(all) struct Wallet {
  id : Int64
  owner : String
  cents : Int64
}

///|
fn wallet_from_row(row : @moondb.Row) -> Wallet raise @moondb.DbError {
  { id: row.int64(0), owner: row.text(1), cents: row.int64(2), }
}

///|
fn wallet_to_columns(w : Wallet) -> Array[(String, @moondb.Value)] {
  [
    ("id", @moondb.Int64(w.id)),
    ("owner", @moondb.Text(w.owner)),
    ("cents", @moondb.Int64(w.cents)),
  ]
}

///|
let wallet_model : @moonorm.Model[Wallet] = @moonorm.Model::new(
  "wallet",
  [
    @moonorm.column("id", BigIntType, primary_key=true, autoincrement=true),
    @moonorm.column("owner", TextType, nullable=false),
    @moonorm.column("cents", BigIntType, nullable=false),
  ],
  wallet_from_row,
  wallet_to_columns,
)

///|
/// The two rules the ledger has, written where a second writer cannot get past
/// them: a balance may not go below zero, and it may not hold more than a
/// thousand currency units. A handler can be raced; a CHECK cannot.
pub fn migrate(sess : @moonorm.Session) -> Unit raise @moondb.DbError {
  let ddl =
    #|CREATE TABLE IF NOT EXISTS wallet (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  owner TEXT NOT NULL,
    #|  cents INTEGER NOT NULL CHECK (cents >= 0),
    #|  CHECK (cents <= 100000)
    #|)
  sess.execute(ddl, []) |> ignore
}

///|
/// One page, in id order so that two pages of the same table cannot overlap. The
/// bounds are clamped here, where the number arrives from the wire, not where the
/// statement is built.
pub fn page(
  sess : @moonorm.Session,
  limit : Int32,
  offset : Int32,
) -> Array[Wallet] raise @moondb.DbError {
  let take = if limit < 1 { 1 } else if limit > 100 { 100 } else { limit }
  let skip = if offset < 0 { 0 } else { offset }
  sess.fetch_as(
    wallet_model,
    wallet_model.select().order_by("id", Asc).limit(take).offset(skip),
  )
}

///|
/// How many rows there are. The count is written as SQL because it is one number
/// about a table, not a column of a row: a projection would have to carry the
/// model's columns along with it.
pub fn count(sess : @moonorm.Session) -> Int64 raise @moondb.DbError {
  let rows = sess.query("SELECT COUNT(*) FROM wallet", [])
  if rows.length() == 0 {
    0L
  } else {
    rows[0].int64(0)
  }
}

///|
/// One wallet, read from the table rather than from the session's identity map.
/// A ledger is read after it is written, and a cached row would answer with the
/// balance from before the transfer — the one thing this endpoint must not do.
pub fn find(
  sess : @moonorm.Session,
  id : Int64,
) -> Wallet? raise @moondb.DbError {
  let rows = sess.fetch_as(
    wallet_model,
    wallet_model.select().eq("id", @moondb.Int64(id)).limit(1),
  )
  if rows.length() == 0 {
    None
  } else {
    Some(rows[0])
  }
}

///|
/// Move money: two statements, one bracket. The debit runs first, so a credit that
/// the table refuses leaves the debit behind unless the bracket takes it back —
/// which is the only reason this function exists instead of two calls.
pub fn transfer_funds(
  sess : @moonorm.Session,
  from : Int64,
  to : Int64,
  cents : Int64,
) -> Unit raise @moondb.DbError {
  sess.transaction(() => {
    sess.execute("UPDATE wallet SET cents = cents - ? WHERE id = ?", [
      @moondb.Int64(cents),
      @moondb.Int64(from),
    ])
    |> ignore
    sess.execute("UPDATE wallet SET cents = cents + ? WHERE id = ?", [
      @moondb.Int64(cents),
      @moondb.Int64(to),
    ])
    |> ignore
  })
}
