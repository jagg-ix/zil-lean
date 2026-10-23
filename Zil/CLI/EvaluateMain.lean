import Zil.Evaluation.Architecture
import Zil.Edn.Reader

/-!
# `zilEvaluate --model FILE [--measurements FILE] [--output FILE|-]`

Reads a placement model and measurements (JSON, or EDN for files ending in `.edn`), writes the evaluation report as
JSON, and exits 1 when it recommends a change (which always needs human approval), 0 when it does not, 2 on error.
-/

open Zil.Json Zil.Evaluation

private def usage : String :=
  "zilEvaluate --model FILE [--measurements FILE] [--output FILE|-]\n" ++
  "Files are JSON, or EDN when the name ends in .edn. Measurements are an array of measurement objects."

private def load (path : String) : IO J := do
  let text ← IO.FS.readFile path
  let parsed := if path.endsWith ".edn" then Zil.Edn.readCanonical text else Zil.Json.parse text
  match parsed with
  | .ok value => pure value
  | .error message => throw (IO.userError s!"invalid-command: cannot read {path}: {message}")

private structure Options where
  model : Option String := none
  measurements : Option String := none
  output : String := "-"
  help : Bool := false

private def parseOptions : List String → Options → IO Options
  | [], o => pure o
  | "--model" :: v :: rest, o => parseOptions rest { o with model := some v }
  | "--measurements" :: v :: rest, o => parseOptions rest { o with measurements := some v }
  | "--output" :: v :: rest, o => parseOptions rest { o with output := v }
  | ("--help" :: _) , o => pure { o with help := true }
  | ("-h" :: _), o => pure { o with help := true }
  | flag :: _, _ => throw (IO.userError s!"invalid-command: unknown or incomplete evaluation option {flag}")

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  try
    let options ← parseOptions args {}
    if options.help then
      IO.println usage
      return (0 : UInt32)
    let some modelPath := options.model | throw (IO.userError s!"invalid-command: --model is required\n{usage}")
    let model ← match parseModel (← load modelPath) with
      | .ok m => pure m
      | .error message => throw (IO.userError s!"evaluation-error: {message}")
    let measurements ← match options.measurements with
      | some path =>
          match parseMeasurements model (← load path) with
          | .ok m => pure m
          | .error message => throw (IO.userError s!"measurement-error: {message}")
      | none => pure #[]
    let (report, changes) := evaluate model measurements
    let text := write (escapeSlash := false) report ++ "\n"
    if options.output == "-" then IO.print text
    else
      let path : System.FilePath := options.output
      if let some parent := path.parent then IO.FS.createDirAll parent
      IO.FS.writeFile path text
    return if changes > 0 then (1 : UInt32) else 0
  catch error =>
    IO.eprintln s!"{error}"
    return (2 : UInt32)
