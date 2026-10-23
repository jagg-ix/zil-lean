import Zil.Plugin.Registry
import Zil.Process.Run
import Zil.Edn.Reader
import Zil.Store.ControlEvent
import Zil.Control.Durable

/-!
# Extensions

The reference extensions (a repository scanner, a report exporter, an external-solver adapter, the SQLite event-store
commands), the adapter for an extension that is a separate command, and the loader that turns a manifest into a live
extension. A `lean` manifest names one of the compiled-in entrypoints; an `external` manifest names a command.
-/

namespace Zil.Plugin

open Zil.Json Zil.Crypto

private def fail (kind message : String) : IO α := throw (IO.userError s!"{kind}: {message}")

/-! ## Paths and files -/

/-- An absolute, lexically normalized path (symbolic links are not resolved). -/
def absolutePath (path : System.FilePath) : IO System.FilePath := do
  let cwd ← IO.currentDir
  let full := if path.isAbsolute then path else cwd / path
  let mut parts : Array String := #[]
  for part in full.toString.splitOn "/" do
    if part == "" || part == "." then pure ()
    else if part == ".." then parts := parts.pop
    else parts := parts.push part
  return System.FilePath.mk ("/" ++ "/".intercalate parts.toList)

private def fileSha256 (path : System.FilePath) : IO String := do
  return Sha256.prefixed (← IO.FS.readBinFile path)

private def isRegularFile (path : System.FilePath) : IO Bool := do
  try return (← path.metadata).type == .file catch _ => return false

/-- Clojure's printed form of a string, as `(str ["a" 1])` shows it. -/
private def printedString (text : String) : String := Id.run do
  let mut out := "\""
  for c in text.toList do
    if c == '"' then out := out ++ "\\\""
    else if c == '\\' then out := out ++ "\\\\"
    else if c == '\n' then out := out ++ "\\n"
    else if c == '\t' then out := out ++ "\\t"
    else if c == '\r' then out := out ++ "\\r"
    else out := out.push c
  return out ++ "\""

/-! ## Repository scanner -/

def scanSchema : String := "ZIL-REPOSITORY-SCAN/1"

private partial def walkFiles (root dir : System.FilePath) (excluded : Array String) : IO (Array (String × System.FilePath)) := do
  let mut out := #[]
  for entry in ← dir.readDir do
    let path := entry.path
    let relative := (path.toString.drop (root.toString.length + 1)).toString
    let hidden := relative == ".git" || relative.startsWith ".git/" ||
      excluded.any fun e => relative == e || relative.startsWith (e ++ "/")
    if hidden then continue
    let info ← path.symlinkMetadata
    if info.type == .dir then out := out ++ (← walkFiles root path excluded)
    else if (← isRegularFile path) then out := out.push (relative, path)
  return out

def scanRepository (root : System.FilePath) (config : J) : IO J := do
  let root ← absolutePath root
  unless ← root.isDir do fail "extension-input-error" s!"repository scan root is not a directory ({root})"
  let excluded : Array String :=
    match config.get? "exclude" with
    | some (.arr items) => items.filterMap J.asStr?
    | _ => #[".lake", "target"]
  let files := (← walkFiles root root excluded).qsort fun a b => compareKeys a.1 b.1 == .lt
  let mut entries : Array J := #[]
  let mut lines : Array String := #[]
  for (relative, path) in files do
    let size := (← path.metadata).byteSize.toNat
    let sha ← fileSha256 path
    entries := entries.push (.obj #[("path", .str relative), ("bytes", .int size), ("sha256", .str sha)])
    lines := lines.push s!"[{printedString relative} {size} {printedString sha}]"
  return .obj #[("schema", .str scanSchema), ("root-label", .str (root.fileName.getD ".")),
    ("file-count", .int entries.size), ("content-sha256", .str (Sha256.ofText ("\n".intercalate lines.toList))),
    ("entries", .arr entries)]

private def repositoryScanner (manifest : Manifest) (config : J) : Extension :=
  { manifest, capabilities := #["evidence-producer", "repository-scanner"],
    commands := #[("repository-scan", { summary := "Produce a deterministic repository file inventory",
                                         arguments := #["root"], authority := "operational" })],
    invoke := fun command arguments => do
      unless command == "repository-scan" do fail "unknown-extension-command" s!"unsupported repository scanner command ({command})"
      unless arguments.size == 1 do fail "extension-input-error" "repository-scan requires one root argument"
      scanRepository arguments[0]! config,
    evidence := some fun request => do
      let root := (request.getStr? "root").getD "."
      let report ← scanRepository root config
      return #[{ manifest, role := "repository-scan",
                 subject := (request.getStr? "subject").getD s!"repository:{(report.getStr? "root-label").getD ""}",
                 inputSha256 := report.getStr? "content-sha256", payload := write report,
                 metadata := .obj #[("file-count", report.get? "file-count" |>.getD .null)] }] }

/-! ## Report exporter -/

def reportSchema : String := "ZIL-REPORT-EXPORT/1"

private def isSimpleKeyword (key : String) : Bool :=
  match key.toList with
  | first :: rest =>
      (first.isAlpha || first == '_') && rest.all (fun c => c.isAlphanum || c == '_' || c == '-' || c == '.')
  | [] => false

/-- EDN text of canonical JSON: simple object keys become keywords. -/
partial def ednText : J → String
  | .null => "nil"
  | .bool b => toString b
  | .int n => toString n
  | .number t => t
  | .str s => printedString s
  | .arr items => "[" ++ " ".intercalate (items.toList.map ednText) ++ "]"
  | .obj fields =>
      "{" ++ ", ".intercalate (fields.toList.map fun (k, v) => (if isSimpleKeyword k then ":" ++ k else printedString k) ++ " " ++ ednText v) ++ "}"

private def readReport (path : System.FilePath) : IO J := do
  let text ← IO.FS.readFile path
  let parsed := if path.toString.toLower.endsWith ".json" then Zil.Json.parse text else Zil.Edn.readCanonical text
  match parsed with
  | .ok value => pure value
  | .error message => fail "extension-input-error" s!"cannot read report {path}: {message}"

def exportReport (input output : System.FilePath) (format : String) : IO J := do
  let value ← readReport input
  let canonicalValue ← match canonical value with | .ok v => pure v | .error m => fail "extension-input-error" m
  let rendered ← match format.toLower with
    | "json" => pure (write canonicalValue ++ "\n")
    | "edn" => pure (ednText canonicalValue ++ "\n")
    | _ => fail "extension-input-error" s!"report format must be json or edn ({format})"
  let target ← absolutePath output
  let parent := target.parent.getD "/"
  IO.FS.createDirAll parent
  let (handle, temporary) ← IO.FS.createTempFile
  handle.putStr rendered
  handle.flush
  -- a rename within one filesystem is atomic; a temporary file elsewhere is copied into place first
  let staging := parent / s!".zil-report-{(Sha256.hex rendered.toUTF8).take 16}.tmp"
  IO.FS.writeFile staging rendered
  IO.FS.rename staging target
  try IO.FS.removeFile temporary catch _ => pure ()
  return .obj #[("schema", .str reportSchema), ("input", .str input.toString), ("input-sha256", .str (← fileSha256 input)),
    ("output", .str target.toString), ("output-sha256", .str (← fileSha256 target)), ("format", .str format.toLower),
    ("bytes", .int rendered.toUTF8.size)]

private def reportExporter (manifest : Manifest) : Extension :=
  { manifest, capabilities := #["evidence-producer", "report-exporter"],
    commands := #[("report-export", { summary := "Export a canonical JSON or EDN report",
                                       arguments := #["input-path", "output-path", "format"], authority := "operational" })],
    invoke := fun command arguments => do
      unless command == "report-export" do fail "unknown-extension-command" s!"unsupported report exporter command ({command})"
      unless arguments.size == 3 do fail "extension-input-error" "report-export requires input, output, and format arguments"
      exportReport arguments[0]! arguments[1]! arguments[2]!,
    evidence := some fun request => do
      let text (key : String) : IO String :=
        match request.getStr? key with | some t => pure t | none => fail "extension-input-error" s!"evidence request lacks {key}"
      let report ← exportReport (← text "input-path") (← text "output-path") (← text "format")
      return #[{ manifest, role := "report-export",
                 subject := (request.getStr? "subject").getD s!"artifact:{(report.getStr? "output").getD ""}",
                 inputSha256 := report.getStr? "input-sha256", payload := write report,
                 metadata := .obj #[("format", report.get? "format" |>.getD .null), ("bytes", report.get? "bytes" |>.getD .null)] }] }

/-! ## External solver -/

def toolSchema : String := "ZIL-EXTERNAL-TOOL/1"

/-- Run one allowlisted proof tool without a shell and report exactly what it printed. -/
def runTool (config : J) (tool inputPath : String) : IO J := do
  let some descriptor := (config.get? "tools").bind (·.get? tool)
    | fail "extension-input-error" s!"external tool is not allowlisted ({tool})"
  let command := match descriptor.get? "command" with | some (.arr items) => items.filterMap J.asStr? | _ => #[]
  if command.isEmpty then fail "extension-configuration-error" s!"external tool command must be a nonempty vector ({tool})"
  let timeout := match descriptor.get? "timeout-ms" with | some (.int n) => n.toNat | _ => 30000
  if timeout == 0 then fail "extension-configuration-error" s!"external tool timeout must be positive ({tool})"
  let invocation := command.map fun word => if word == "{input}" then inputPath else word
  let result ← Process.run invocation[0]! (invocation.extract 1 invocation.size) timeout
  return .obj #[("command", .arr (invocation.map .str)), ("exit", .int result.exitCode), ("input", .str inputPath),
    ("input-sha256", .str (← fileSha256 inputPath)), ("ok", .bool (result.exitCode == 0)), ("schema", .str toolSchema),
    ("stderr", .str result.stderr), ("stderr-sha256", .str (Sha256.ofText result.stderr)),
    ("stdout", .str result.stdout), ("stdout-sha256", .str (Sha256.ofText result.stdout)), ("tool", .str tool)]

private def externalSolver (manifest : Manifest) (config : J) : Extension :=
  { manifest, capabilities := #["evidence-producer", "external-solver"],
    commands := #[("solver-run", { summary := "Run one configured external proof tool without a shell",
                                    arguments := #["tool", "input-path"], authority := "external" })],
    invoke := fun command arguments => do
      unless command == "solver-run" do fail "unknown-extension-command" s!"unsupported external solver command ({command})"
      unless arguments.size == 2 do fail "extension-input-error" "solver-run requires tool and input-path arguments"
      runTool config arguments[0]! arguments[1]!,
    evidence := some fun request => do
      let text (key : String) : IO String :=
        match request.getStr? key with | some t => pure t | none => fail "extension-input-error" s!"evidence request lacks {key}"
      let tool ← text "tool"
      let input ← text "input-path"
      let report ← runTool config tool input
      return #[{ manifest, authority := some "external", assurance := some "externally-attested",
                 role := (request.getStr? "role").getD "external-proof-tool",
                 subject := (request.getStr? "subject").getD s!"artifact:{input}",
                 inputSha256 := report.getStr? "input-sha256", payload := write report,
                 metadata := .obj #[("tool", .str tool), ("exit", report.get? "exit" |>.getD .null),
                                    ("ok", report.get? "ok" |>.getD .null)] }] }

/-! ## SQLite event store -/

private def sqliteEventStore (manifest : Manifest) : Extension :=
  { manifest, capabilities := #["control-event-store", "snapshot-store"],
    commands := #[("event-store-status", { summary := "Read and verify one control event stream",
                                            arguments := #["database", "stream"], authority := "operational" }),
                  ("event-store-project", { summary := "Materialize the operational workflow projection",
                                             arguments := #["database", "stream"], authority := "operational" })],
    invoke := fun command arguments => do
      unless arguments.size == 2 do fail "extension-input-error" "event store commands require database and stream"
      let database : System.FilePath := arguments[0]!
      let stream := arguments[1]!
      match command with
      | "event-store-status" =>
          let revision ← Store.ControlEvent.withConnection database fun s => Store.ControlEvent.currentRevision s stream
          return .obj #[("stream", .str stream), ("revision", .int revision),
                        ("integrity", ← Store.ControlEvent.verifyStore database stream)]
      | "event-store-project" => Control.Durable.workflowStatus database stream
      | _ => fail "unknown-extension-command" s!"unsupported SQLite event store command ({command})" }

/-! ## An extension that is a separate command -/

/-- Call the command with one JSON request on its input and read one JSON document from its output. -/
private def callExternal (cmd : String) (args : Array String) (cwd : System.FilePath) (timeoutMs : Nat) (request : J) : IO J := do
  let result ← Process.run cmd args timeoutMs (cwd := some cwd) (stdin := some (write (escapeSlash := false) request ++ "\n"))
  unless result.exitCode == 0 do
    fail "extension-failure" s!"{cmd} exited with {result.exitCode}: {result.stderr.take 300}"
  match Zil.Json.parse result.stdout with
  | .ok value => pure value
  | .error message => fail "extension-failure" s!"{cmd} printed something that is not JSON: {message}"

private def externalExtension (manifest : Manifest) (config : J) (manifestDir : System.FilePath) : IO Extension := do
  let words := (manifest.entrypoint.splitOn " ").filter (· ≠ "")
  let some cmd := words.head? | fail "extension-load-error" "external entrypoint is empty"
  let local_ := manifestDir / cmd
  let program ← if ← local_.pathExists then pure (← absolutePath local_).toString else pure cmd
  let manifestDir ← absolutePath manifestDir
  let args := (words.drop 1).toArray
  let timeout := match config.get? "timeout-ms" with | some (.int n) => n.toNat | _ => 30000
  let call (request : J) := callExternal program args manifestDir timeout request
  let described ← call (.obj #[("op", .str "describe")])
  let capabilities := match described.get? "capabilities" with | some (.arr items) => items.filterMap J.asStr? | _ => #[]
  let commands : Array (String × CommandDescriptor) :=
    match described.get? "commands" with
    | some (.obj fields) => fields.map fun (name, d) =>
        (name, { summary := (d.getStr? "summary").getD "",
                 arguments := match d.get? "arguments" with | some (.arr a) => a.filterMap J.asStr? | _ => #[],
                 authority := manifest.authority })
    | _ => #[]
  let producesEvidence := described.get? "evidence" == some (.bool true)
  let produce : J → IO (Array Evidence.Request) := fun request => do
    let answer ← call (.obj #[("op", .str "evidence"), ("request", request), ("config", config)])
    let parts := match answer with | .arr items => items | single => #[single]
    return parts.map fun part =>
      { manifest, role := (part.getStr? "role").getD "", subject := (part.getStr? "subject").getD "",
        inputSha256 := part.getStr? "input_sha256", payload := (part.getStr? "payload").getD "",
        metadata := (part.get? "metadata").getD (.obj #[]) }
  let invoke : String → Array String → IO J := fun command arguments =>
    call (.obj #[("op", .str "invoke"), ("command", .str command), ("arguments", .arr (arguments.map .str)), ("config", config)])
  return { manifest, capabilities, commands, invoke, evidence := if producesEvidence then some produce else none }

/-- The entrypoints compiled into this program. -/
def entrypoints : List String := ["repository-scanner", "report-exporter", "external-solver", "sqlite-event-store"]

/-- Turn a manifest into a live extension. -/
def loadExtension (manifestPath : System.FilePath) (config : J) : IO Extension := do
  let manifest ← Zil.Plugin.read manifestPath
  let dir := manifestPath.parent.getD "."
  match manifest.runtime, manifest.entrypoint with
  | "lean", "repository-scanner" => return repositoryScanner manifest config
  | "lean", "report-exporter" => return reportExporter manifest
  | "lean", "external-solver" => return externalSolver manifest config
  | "lean", "sqlite-event-store" => return sqliteEventStore manifest
  | "lean", other =>
      fail "extension-load-error" s!"entrypoint {other} is not compiled into this program (available: {entrypoints}) ({manifestPath})"
  | "external", _ => externalExtension manifest config dir
  | other, _ => fail "extension-load-error" s!"runtime {other} cannot be loaded ({manifestPath})"

end Zil.Plugin
