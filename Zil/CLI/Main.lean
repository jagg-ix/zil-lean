import Zil.CLI.Core

namespace Zil.CLI

private def usage : String :=
  "zil <summary|closure|check|query|export|repl|apply-delta> <snapshot.zilx> [argument]\n" ++
  "  check/query argument uses canonical relation encoding\n" ++
  "  export argument is souffle or prolog\n" ++
  "  apply-delta <snapshot.zilx> <delta.zild> <output.zilx>"

private def loadSession (path : String) : IO Session := do
  let text ← IO.FS.readFile path
  match Zil.Interop.decodeEnvelope text with
  | .ok envelope => pure ⟨envelope⟩
  | .error error => throw <| IO.userError error

private partial def repl (session : Session) : IO Unit := do
  IO.print "zil> "
  let line ← (← IO.getStdin).getLine
  let line := line.trim
  if line == "quit" || line == "exit" then pure ()
  else
    match parseCommand line with
    | .ok command => IO.println (execute session command)
    | .error error => IO.eprintln error
    repl session

private def runBatch (command snapshot : String) (argument : Option String) : IO Unit := do
  let session ← loadSession snapshot
  let parsed ← match command with
    | "summary" => pure Command.summary
    | "closure" => pure Command.closure
    | "check" =>
        match argument with
        | some value => match parseCommand ("check " ++ value) with
          | .ok command => pure command
          | .error error => throw <| IO.userError error
        | none => throw <| IO.userError "check requires a canonical relation"
    | "query" =>
        match argument with
        | some value => match parseCommand ("query " ++ value) with
          | .ok command => pure command
          | .error error => throw <| IO.userError error
        | none => throw <| IO.userError "query requires a canonical relation"
    | "export" =>
        match argument with
        | some "souffle" => pure (.export .souffle)
        | some "prolog" => pure (.export .prolog)
        | _ => throw <| IO.userError "export requires souffle or prolog"
    | _ => throw <| IO.userError s!"unknown command {command}"
  IO.println (execute session parsed)

private def applyDeltaFile (snapshotPath deltaPath outputPath : String) : IO Unit := do
  let snapshotText ← IO.FS.readFile snapshotPath
  let deltaText ← IO.FS.readFile deltaPath
  let snapshot ← match Zil.Interop.decodeEnvelope snapshotText with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let delta ← match Zil.Interop.decodeDelta deltaText with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let updated ← match Zil.Interop.applyDelta snapshot delta with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  IO.FS.writeFile outputPath (Zil.Interop.encodeEnvelope updated)

end Zil.CLI

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["repl", snapshot] => Zil.CLI.repl (← Zil.CLI.loadSession snapshot); pure 0
    | ["apply-delta", snapshot, delta, output] =>
        Zil.CLI.applyDeltaFile snapshot delta output; pure 0
    | [command, snapshot] => Zil.CLI.runBatch command snapshot none; pure 0
    | [command, snapshot, argument] => Zil.CLI.runBatch command snapshot (some argument); pure 0
    | _ => IO.eprintln Zil.CLI.usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
