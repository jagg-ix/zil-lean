import Std.Time
import Zil.Runtime.Interop

/-!
# `zilIngest`: datasources, data files and the revision log

    zilIngest run <model.zc> [--lib DIR] [--source NAME]... [--revision N] [--timestamp MS] [--event NAME]
                             [--polls N] [--initial-revision N] [--module NAME]
                             [--json FILE|-] [--zc FILE] [--zilr FILE]
    zilIngest import-data <input> [output.zc|-] [module_name] [format] [record_prefix]
    zilIngest convert <input> <format> [output|-] [--from FORMAT]

`run` reads every `DATASOURCE` of the model once (an `interval` source `--polls` times), prints a summary and writes the
facts and causal edges as JSON, as ZIL source and as a `ZILR/1` revision log. Exit status 2 is a malformed command or an
input that cannot be read.
-/

open Zil.Json Zil.Runtime Zil.Runtime.Ingest

private def usage : String :=
  "zilIngest run <model.zc> [--lib DIR] [--source NAME]... [--revision N] [--timestamp MS] [--event NAME]\n" ++
  "                         [--polls N] [--initial-revision N] [--module NAME] [--json FILE|-] [--zc FILE] [--zilr FILE]\n" ++
  "zilIngest import-data <input> [output.zc|-] [module_name] [format] [record_prefix]\n" ++
  "zilIngest convert <input> <format> [output|-] [--from FORMAT]"

private structure RunOptions where
  model : String := ""
  lib : Option String := none
  sources : Array String := #[]
  revision : Option Int := none
  timestamp : Option Int := none
  event : Option String := none
  polls : Nat := 1
  initialRevision : Option Int := none
  moduleName : Option String := none
  json : Option String := none
  zc : Option String := none
  zilr : Option String := none

private def intArg (flag value : String) : Except String Int :=
  match value.toInt? with | some n => .ok n | none => .error s!"{flag} needs a number, got {value}"

private partial def parseRun (args : List String) (o : RunOptions) : Except String RunOptions :=
  match args with
  | [] => if o.model.isEmpty then .error "run needs a model" else .ok o
  | "--lib" :: v :: rest => parseRun rest { o with lib := some v }
  | "--source" :: v :: rest => parseRun rest { o with sources := o.sources.push v }
  | "--revision" :: v :: rest => do parseRun rest { o with revision := some (← intArg "--revision" v) }
  | "--timestamp" :: v :: rest => do parseRun rest { o with timestamp := some (← intArg "--timestamp" v) }
  | "--initial-revision" :: v :: rest => do parseRun rest { o with initialRevision := some (← intArg "--initial-revision" v) }
  | "--polls" :: v :: rest => match v.toNat? with
      | some n => if n == 0 then .error "--polls needs at least 1" else parseRun rest { o with polls := n }
      | none => .error s!"--polls needs a number, got {v}"
  | "--event" :: v :: rest => parseRun rest { o with event := some v }
  | "--module" :: v :: rest => parseRun rest { o with moduleName := some v }
  | "--json" :: v :: rest => parseRun rest { o with json := some v }
  | "--zc" :: v :: rest => parseRun rest { o with zc := some v }
  | "--zilr" :: v :: rest => parseRun rest { o with zilr := some v }
  | flag :: _ => if flag.startsWith "--" then .error s!"unknown or incomplete option {flag}"
      else if o.model.isEmpty then parseRun args.tail! { o with model := flag }
      else .error s!"unexpected argument {flag}"

private def writeTo (target : String) (text : String) : IO Unit := do
  if target == "-" then IO.print text
  else
    if let some parent := (System.FilePath.mk target).parent then IO.FS.createDirAll parent
    IO.FS.writeFile target text

private def loadLibraries (directory : String) : IO (Array Zil.Parser.MacroProgram.LibrarySource) := do
  let entries := (← (System.FilePath.mk directory).readDir).filter (·.fileName.endsWith ".zc")
  let sorted := entries.qsort fun a b => a.fileName < b.fileName
  sorted.mapM fun entry => do pure { label := "lib/" ++ entry.fileName, text := ← IO.FS.readFile entry.path }

private def nowMs : IO Int := do
  let t ← Std.Time.Timestamp.now
  pure t.toMillisecondsSinceUnixEpoch.val

private def runCommand (o : RunOptions) : IO UInt32 := do
  let text ← IO.FS.readFile (System.FilePath.mk o.model)
  let parsed ← match o.lib with
    | none => pure (Zil.Parser.DeclarationProgram.parseText text)
    | some dir => pure (Zil.Parser.DeclarationProgram.parseTextWithLibraries (← loadLibraries dir) o.model text)
  let program ← match parsed with | .ok p => pure p | .error e => throw (IO.userError e.render)
  let specs ← match datasourceSpecs program with | .ok s => pure s | .error e => throw (IO.userError e)
  let selected := if o.sources.isEmpty then specs else specs.filter fun s => o.sources.contains s.name || o.sources.contains s.id
  for name in o.sources do
    unless specs.any (fun s => s.name == name || s.id == name) do throw (IO.userError s!"no DATASOURCE named {name}")
  let timestamp ← match o.timestamp with | some t => pure t | none => nowMs
  let initial := o.initialRevision.getD timestamp
  let mut results : Array SourceResult := #[]
  for spec in selected do
    let interval := (tokenAttr? spec ["poll_mode"]) == some "interval"
    let runs := if interval then o.polls else 1
    let every := match attr? spec ["poll_every_ms", "interval_ms"] with | some (.int n) => n.toNat | _ => 5000
    for k in [0:runs] do
      if k > 0 then IO.sleep every.toUInt32
      let revision := match o.revision with
        | some r => r
        | none => if interval then initial + k + 1 else timestamp
      results := results.push (← ingestOnce spec revision (if k == 0 then timestamp else timestamp + k) o.event)
  let document := runJson results
  let summary := match document with
    | .obj fields => J.obj (fields.filter fun (k, _) => k != "fact_list" && k != "before_edge_list")
    | other => other
  let moduleName := o.moduleName.getD ((program.moduleName.map (·.toString)).getD "ingest.facts")
  if let some target := o.json then writeTo target (write document (escapeSlash := false) ++ "\n")
  if let some target := o.zc then
    writeTo target (renderZc moduleName (results.foldl (fun acc r => acc ++ r.facts) #[]))
  if let some target := o.zilr then
    match toRevisionStore moduleName results with
    | .error message => throw (IO.userError message)
    | .ok (store, dropped) =>
        writeTo target (Zil.Codec.Revision.encodeStore store)
        if dropped > 0 then IO.eprintln s!"{dropped} causal edge(s) name an event with no fact and are not in the revision log"
  unless o.json == some "-" || o.zc == some "-" || o.zilr == some "-" do
    IO.println (write summary (escapeSlash := false))
  return 0

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  try
    match args with
    | "run" :: rest =>
        match parseRun rest {} with
        | .error message => IO.eprintln message; IO.eprintln usage; pure 2
        | .ok options => runCommand options
    | "import-data" :: input :: rest =>
        let output := match rest with | out :: _ => if out == "-" then none else some out | [] => none
        let moduleName := match rest with | _ :: m :: _ => m | _ => "interop.import"
        let format := match rest with | _ :: _ :: f :: _ => some f | _ => none
        let prefix_ := match rest with | _ :: _ :: _ :: p :: _ => p | _ => "interop:record"
        let imported ← Interop.importData input format moduleName prefix_
        match output with
        | some out =>
            writeTo out imported.text
            IO.println (write (.obj #[("ok", .bool true), ("input", .str input), ("format", .str imported.format.name),
              ("module", .str moduleName), ("records", .int imported.records), ("facts", .int imported.facts),
              ("output_path", .str out)]) (escapeSlash := false))
        | none => IO.print imported.text
        pure 0
    | "convert" :: input :: format :: rest =>
        let (positional, from_) := match rest with
          | [out, "--from", f] => ([out], some f)
          | ["--from", f] => ([], some f)
          | other => (other, none)
        let some to := Codec.normalizeFormat format | IO.eprintln s!"unknown format {format}"; pure 2
        let source ← match from_ with
          | some f => match Codec.normalizeFormat f with
              | some x => pure (some x)
              | none => IO.eprintln s!"unknown format {f}"; return 2
          | none => pure (Interop.inferFormat input)
        let some source := source | IO.eprintln "Could not infer the input format from the file name; pass --from"; pure 2
        match Interop.convert (← IO.FS.readFile (System.FilePath.mk input)) source to with
        | .error message => IO.eprintln message; pure 2
        | .ok text =>
            match positional with
            | out :: _ => if out == "-" then IO.println text else writeTo out (text ++ "\n")
            | [] => IO.println text
            pure 0
    | _ => IO.eprintln usage; pure 2
  catch error : IO.Error =>
    IO.eprintln (toString error)
    pure 2
