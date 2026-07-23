import Zil.Exchange.Dispatch

private def responseForLine (line : String) : IO Zil.Exchange.Response := do
  match Zil.Exchange.Request.parse line.trim with
  | .ok request => Zil.Exchange.dispatch request
  | .error error => pure (Zil.Exchange.Response.transportFailure error)

private def writeResponse (stdout : IO.FS.Stream) (response : Zil.Exchange.Response) : IO Unit := do
  stdout.putStrLn response.render
  stdout.flush

private partial def serve
    (stdin stdout : IO.FS.Stream) : IO UInt32 := do
  let line ← stdin.getLine
  if line.isEmpty then
    pure 0
  else
    let response ← responseForLine line
    writeResponse stdout response
    serve stdin stdout

private def once (stdin stdout : IO.FS.Stream) : IO UInt32 := do
  let line ← stdin.getLine
  if line.isEmpty then
    writeResponse stdout (Zil.Exchange.Response.transportFailure "expected one JSON request line")
    pure 1
  else
    let response ← responseForLine line
    writeResponse stdout response
    pure (if response.status == "ok" then 0 else 1)

private def usage : String :=
  "zilWorker [--stdio|--once]"

/-- Native JSON Lines worker for the Clojure operational control plane. -/
def main (args : List String) : IO UInt32 := do
  try
    let stdin ← IO.getStdin
    let stdout ← IO.getStdout
    match args with
    | [] => serve stdin stdout
    | ["--stdio"] => serve stdin stdout
    | ["--once"] => once stdin stdout
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
