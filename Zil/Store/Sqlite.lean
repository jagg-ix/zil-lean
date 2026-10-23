import Zil.Json.Ordered

/-!
# SQLite sessions

A durable store needs transactions and a lock, which Lean's standard library does not offer. A session here is one
long-lived `sqlite3` process: statements go to its standard input, results come back as JSON on its standard output, and
the decision logic stays in Lean. Text is sent as hex (`CAST(X'..' AS TEXT)`), so no value can change the statement.

The `sqlite3` command-line shell must be on `PATH`; `bin/zil doctor` reports it.
-/

namespace Zil.Store.Sqlite

open Zil.Json

structure Session where
  child : IO.Process.Child { stdin := .piped, stdout := .piped, stderr := .piped }
  counter : IO.Ref Nat

/-- Hex digits of the UTF-8 bytes of `text`. -/
private def hexOfText (text : String) : String :=
  let digit (n : UInt8) : Char := if n < 10 then Char.ofNat (48 + n.toNat) else Char.ofNat (87 + n.toNat)
  text.toUTF8.foldl (fun acc byte => acc.push (digit (byte >>> 4)) |>.push (digit (byte &&& 15))) ""

/-- A SQL text literal that cannot be broken out of. -/
def text (value : String) : String := s!"CAST(X'{hexOfText value}' AS TEXT)"

/-- A SQL integer literal. -/
def int (value : Int) : String := toString value

/-- A SQL integer literal, or NULL. -/
def optionalInt (value : Option Int) : String :=
  match value with
  | some n => toString n
  | none => "NULL"

/-- Start a session on the database at `path`, creating its directory. WAL mode, foreign keys on, five seconds of
patience for a competing writer. -/
def open_ (path : System.FilePath) : IO Session := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let child ← IO.Process.spawn
    { cmd := "sqlite3", args := #["-batch", "-json", "-bail", path.toString],
      stdin := .piped, stdout := .piped, stderr := .piped }
  return { child, counter := ← IO.mkRef 0 }

private def failure (session : Session) (context : String) : IO α := do
  let (_, child) ← session.child.takeStdin
  let message ← child.stderr.readToEnd
  let code ← child.wait
  throw (IO.userError s!"sqlite3 {context} failed (exit {code}): {message.trimAscii}")

/-- Run SQL and return the JSON output it printed, if any. The statements must print at most one result set. -/
private def run (session : Session) (sql : String) : IO String := do
  let n ← session.counter.modifyGet fun n => (n, n + 1)
  let marker := s!"<<zil-done-{n}>>"
  try
    session.child.stdin.putStr (sql ++ "\n")
    session.child.stdin.putStr s!"SELECT '{marker}' AS zil_done;\n"
    session.child.stdin.flush
  catch _ => failure session "write"
  let mut output := ""
  repeat
    let line ← session.child.stdout.getLine
    if line.isEmpty then failure session "read"
    if (line.splitOn marker).length > 1 then break
    output := output ++ line
  return output

/-- Run statements that print nothing. -/
def exec (session : Session) (sql : String) : IO Unit := do
  let output ← run session sql
  unless output.trimAscii.isEmpty do
    throw (IO.userError s!"unexpected output from sqlite3: {output.trimAscii}")

/-- Run one SELECT and return its rows as JSON objects. -/
def query (session : Session) (sql : String) : IO (Array J) := do
  let output ← run session sql
  if output.trimAscii.isEmpty then return #[]
  match parse output with
  | .ok (.arr rows) => return rows
  | .ok _ => throw (IO.userError "sqlite3 printed something other than rows")
  | .error message => throw (IO.userError s!"sqlite3 output is not JSON: {message}")

/-- The first column of the first row, as text. -/
def scalar? (session : Session) (sql : String) (column : String) : IO (Option String) := do
  let rows ← query session sql
  match rows[0]? with
  | some row =>
      match row.get? column with
      | some (.str text) => return some text
      | some (.int n) => return some (toString n)
      | some .null | none => return none
      | some _ => return none
  | none => return none

/-- Close the session, asking the shell to quit and waiting for it. -/
def close (session : Session) : IO Unit := do
  try
    session.child.stdin.putStr ".quit\n"
    session.child.stdin.flush
  catch _ => pure ()
  let (_, child) ← session.child.takeStdin
  let _ ← child.wait

/-- Open a session, run `action`, close it whatever happens. -/
def withSession (path : System.FilePath) (action : Session → IO α) : IO α := do
  let session ← open_ path
  try
    let result ← action session
    close session
    return result
  catch error =>
    try close session catch _ => pure ()
    throw error

/-- Run `action` in an immediate transaction: committed if it returns, rolled back if it throws. -/
def transaction (session : Session) (action : IO α) : IO α := do
  exec session "BEGIN IMMEDIATE;"
  try
    let result ← action
    exec session "COMMIT;"
    return result
  catch error =>
    try exec session "ROLLBACK;" catch _ => pure ()
    throw error

/-- Pragmas every session uses. -/
def prepare (session : Session) : IO Unit := do
  -- journal_mode and busy_timeout print their new value; foreign_keys prints nothing.
  let _ ← query session "PRAGMA journal_mode = WAL;"
  exec session "PRAGMA foreign_keys = ON;"
  let _ ← query session "PRAGMA busy_timeout = 5000;"

end Zil.Store.Sqlite
