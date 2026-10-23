import Zil.Runtime.Codec
import Zil.Parser.DeclarationProgram
import Zil.Process.Run
import Zil.Codec.Revision
import Zil.Parser.Tuple

/-!
# Datasource ingest

A `DATASOURCE` declaration names where records come from:

    DATASOURCE feed [type=file, path="events.json", format=json].
    DATASOURCE probe [type=command, command="uptime", format=text].
    DATASOURCE api [type=rest, url="http://localhost:8080/metrics", format=json, poll_mode=interval, poll_every_ms=5000].
    DATASOURCE run [type=cucumber, path="cucumber-report.json"].

Reading a source once gives records; each record becomes facts about the datasource and, when it names an event, the
event's causal position (`before` lists and vector clocks give `before` edges). Facts carry the revision and event they
were ingested under, so a store of them can be read back at any frontier.

Adapters: `file` (`mode` or `format`: lines, text, edn, json, csv, yaml, kv), `command` (run with `bash -lc`),
`rest` (`mock_response(s)`, a local `path`, or an HTTP `url` fetched with `curl`), and `cucumber` (a Cucumber JSON report).
-/

namespace Zil.Runtime.Ingest

open Zil.Json Zil.JavaText Zil.Runtime.Codec

/-! ## Datasource declarations -/

structure Datasource where
  name : String
  id : String
  type : String
  attrs : Array (String × J)

/-- The text of a declaration string after its escapes (`\"`, `\\`, `\n`, `\t`, `\r`) are read. -/
def unescapeText (raw : String) : String := Id.run do
  let mut out := ""
  let mut rest := raw.toList
  while !rest.isEmpty do
    match rest with
    | '\\' :: e :: tail =>
        match e with
        | 'n' => out := out.push '\n'; rest := tail
        | 't' => out := out.push '\t'; rest := tail
        | 'r' => out := out.push '\r'; rest := tail
        | '"' => out := out.push '"'; rest := tail
        | '\\' => out := out.push '\\'; rest := tail
        | other => out := out.push '\\'; out := out.push other; rest := tail
    | c :: tail => out := out.push c; rest := tail
    | [] => pure ()
  return out

partial def declValueToJ : Zil.DeclValue → J
  | .scalar (.text value) => .str (unescapeText value)
  | .scalar (.integer value) => .int value
  | .scalar (.decimal value) => .number value
  | .scalar (.boolean value) => .bool value
  | value@(.scalar (.term _)) => .str ((Zil.DeclValue.token? value).getD "")
  | .list values | .set values => .arr (values.map declValueToJ)
  | .map entries =>
      .obj (entries.map fun (k, v) => (match declValueToJ k with | .str s => s | other => prStr other, declValueToJ v))

private def datasourceTypes : List String := ["rest", "file", "command", "socket", "websocket", "pipe", "cucumber"]
private def datasourceFormats : List String := ["json", "text", "csv", "edn", "kv", "yaml", "yml"]
private def pollModes : List String := ["event", "interval"]

def attr? (spec : Datasource) (names : List String) : Option J :=
  names.findSome? fun name => (spec.attrs.find? (·.1 == name)).map (·.2)

/-- An attribute that is text or a name, lower case, as a token. -/
def tokenAttr? (spec : Datasource) (names : List String) : Option String :=
  match attr? spec names with
  | some (.str s) => some ((jtrim s).toLower)
  | some .null | none => none
  | some other => some (clojureStr other).toLower

def textAttr? (spec : Datasource) (names : List String) : Option String :=
  match attr? spec names with
  | some (.str s) => some s
  | some .null | none => none
  | some other => some (clojureStr other)

/-- Every `DATASOURCE` declaration of a program, validated. -/
def datasourceSpecs (program : Zil.Program) : Except String (Array Datasource) := do
  let mut out : Array Datasource := #[]
  for declaration in program.declarations do
    if declaration.kind == .datasource then
      let name := declaration.name.toString
      let attrs := declaration.attrs.map fun entry => (entry.key.toString, declValueToJ entry.value)
      let spec : Datasource := { name, id := if name.contains ':' then name else "datasource:" ++ name, type := "", attrs }
      let some type := tokenAttr? spec ["type"]
        | throw s!"DATASOURCE {name} requires a type"
      unless datasourceTypes.contains type do
        throw s!"DATASOURCE {name}: invalid type {type}, expected one of {datasourceTypes}"
      if let some format := tokenAttr? spec ["format"] then
        unless datasourceFormats.contains format do
          throw s!"DATASOURCE {name}: invalid format {format}, expected one of {datasourceFormats}"
      if let some mode := tokenAttr? spec ["poll_mode"] then
        unless pollModes.contains mode do
          throw s!"DATASOURCE {name}: invalid poll_mode {mode}, expected one of {pollModes}"
      out := out.push { spec with type }
  return out

/-! ## Adapters -/

private def failWith {α : Type} (message : String) : IO α := throw (IO.userError message)

private def codecOpts (spec : Datasource) : Opts := spec.attrs

private def formatAttr (spec : Datasource) : IO (Option Format) :=
  match tokenAttr? spec ["format"] with
  | none => pure none
  | some name => match normalizeFormat name with
      | some format => pure (some format)
      | none => failWith s!"unsupported format {name}"

private def decode (spec : Datasource) (format : Format) (text : String) : IO J := do
  match parseString format text (codecOpts spec) with
  | .ok value => pure value
  | .error message => failWith message

private def readText (path : String) : IO String := IO.FS.readFile (System.FilePath.mk path)

private def readFileSource (spec : Datasource) : IO (Array J) := do
  let some path := textAttr? spec ["path", "file"]
    | failWith s!"FILE datasource requires path ({spec.id})"
  let mode := tokenAttr? spec ["mode"]
  let format ← formatAttr spec
  let effective := match mode with
    | some m => m
    | none => (format.map Format.name).getD "lines"
  match effective with
  | "lines" =>
      pure ((splitLines (← readText path)).mapIdx fun index line =>
        .obj #[("line_number", .int (index + 1)), ("line", .str line)])
  | "text" => pure #[.obj #[("text", .str (← readText path))]]
  | other =>
      match normalizeFormat other with
      | some format => pure (recordsFromDecoded (← decode spec format (← readText path)))
      | none => failWith s!"Unsupported FILE mode {other} ({spec.id})"

private def readCommandSource (spec : Datasource) : IO (Array J) := do
  let some command := textAttr? spec ["command", "command_path"]
    | failWith s!"COMMAND datasource requires command ({spec.id})"
  if command.toList.all isJavaWs then failWith s!"COMMAND datasource requires command ({spec.id})"
  let timeout := match attr? spec ["timeout_ms"] with | some (.int n) => n.toNat | _ => 60000
  let result ← Zil.Process.run "bash" #["-lc", command] timeout
  match ← formatAttr spec with
  | none =>
      pure #[.obj #[("exit", .int result.exitCode), ("stdout", .str result.stdout), ("stderr", .str result.stderr)]]
  | some format =>
      let records := recordsFromDecoded (← decode spec format result.stdout)
      pure (records.map fun record =>
        match record with
        | .obj fields =>
            let fields := fields.push ("command_exit", .int result.exitCode)
            .obj (if result.stderr.toList.all isJavaWs then fields else fields.push ("command_stderr", .str result.stderr))
        | other =>
            .obj #[("value", other), ("command_exit", .int result.exitCode), ("command_stderr", .str result.stderr)])

/-- A mock response is JSON, or EDN when it is not JSON. -/
private def decodeMock (text : String) : IO J :=
  match parseString .json text with
  | .ok value => pure value
  | .error _ =>
      match parseString .edn text with
      | .ok value => pure value
      | .error message => failWith s!"mock response is neither JSON nor EDN: {message}"

private def restFormat (spec : Datasource) : IO Format := do
  match ← formatAttr spec with
  | some format => pure format
  | none => pure (if (textAttr? spec ["url"]).isSome then Format.json else Format.text)

private def parseBody (spec : Datasource) (format : Format) (body : String) : IO J :=
  match format with
  | .text => pure (.obj #[("raw", .str body)])
  | other => decode spec other body

private def httpRead (spec : Datasource) (url : String) : IO String := do
  let method := (tokenAttr? spec ["method"]).getD "get"
  let timeoutMs := match attr? spec ["timeout_ms"] with | some (.int n) => n.toNat | _ => 5000
  let format ← restFormat spec
  let body : String := match attr? spec ["body"] with
    | none | some .null => ""
    | some (.str s) => s
    | some other => if format == .text then prStr other else emitString format other (codecOpts spec)
  let headers : Array String := match attr? spec ["headers"] with
    | some (.obj fields) => fields.map fun (k, v) => s!"{k}: {clojureStr v}"
    | _ => #[]
  let args := #["-sS", "--max-time", toString ((timeoutMs + 999) / 1000), "-X", method.toUpper,
      "-o", "/dev/stdout", "-w", "\n%{http_code}"] ++
    (headers.foldl (init := (#[] : Array String)) fun acc header => acc ++ #["-H", header]) ++
    (if method == "get" then #[] else #["--data-binary", "@-"]) ++ #[url]
  let result ← Zil.Process.run "curl" args (timeoutMs + 5000) (stdin := if method == "get" then none else some body)
  if result.exitCode != 0 then failWith s!"HTTP request failed: {jtrim result.stderr}"
  let out := result.stdout
  match out.splitOn "\n" |>.reverse with
  | code :: restRev =>
      let status := (jtrim code).toNat?.getD 0
      let payload := "\n".intercalate restRev.reverse
      if status ≥ 400 then failWith s!"HTTP request failed: status {status}: {payload}"
      pure payload
  | [] => pure ""

private def readRestSource (spec : Datasource) : IO (Array J) := do
  let format ← restFormat spec
  let toRecords (value : J) : Array J := recordsFromDecoded value
  if let some text := textAttr? spec ["mock_responses"] then return toRecords (← decodeMock text)
  if let some text := textAttr? spec ["mock_response"] then return toRecords (← decodeMock text)
  if let some url := textAttr? spec ["url"] then
    return toRecords (← parseBody spec format (← httpRead spec url))
  if let some path := textAttr? spec ["path"] then
    return toRecords (← parseBody spec format (← readText path))
  pure #[]

/-! ### Cucumber reports -/

private def slug (value : String) : String := Id.run do
  let mut out := ""
  let mut inRun := false
  for c in value.toLower.toList do
    if (c.isLower || c.isDigit) && c.toNat < 128 then
      out := out.push c
      inRun := false
    else
      unless inRun do out := out.push '_'
      inRun := true
  let trimmed := String.ofList ((out.toList.dropWhile (· == '_')).reverse.dropWhile (· == '_')).reverse
  if trimmed.toList.all isJavaWs then "unnamed" else trimmed

private def pad3 (n : Nat) : String := let s := toString n; String.ofList (List.replicate (3 - s.length) '0') ++ s

private def stepDuration (step : J) : Except String Int :=
  match (step.get? "result" >>= (·.get? "duration")) with
  | some (.int n) => .ok n
  | some (.number t) => .ok ((t.splitOn ".")[0]!.toInt?.getD 0)
  | some (.str s) =>
      match (jtrim s).toInt? with
      | some n => .ok n
      | none => .error s!"For input string: \"{jtrim s}\""
  | _ => .ok 0

private def readCucumberSource (spec : Datasource) : IO (Array J) := do
  let some path := textAttr? spec ["path", "file"]
    | failWith s!"CUCUMBER datasource requires path ({spec.id})"
  if path.toList.all isJavaWs then failWith s!"CUCUMBER datasource requires path ({spec.id})"
  let payload ← decode spec .json (← readText path)
  let features : Array J ← match payload with
    | .arr items => pure items
    | value@(.obj _) => pure #[value]
    | _ => failWith "Unsupported cucumber payload root"
  let mut records : Array J := #[]
  for (feature, featureIdx) in features.zipIdx do
    let featureName := (feature.getStr? "name").getD "feature"
    let fid := match feature.get? "id" with
      | some (.str s) => s
      | some other@(.int _) => clojureStr other
      | _ => s!"feature_{featureIdx + 1}_{slug ((feature.getStr? "name").getD "feature")}"
    let uri := (feature.getStr? "uri").getD "unknown"
    let scenarios := ((feature.get? "elements" <|> feature.get? "scenarios") >>= J.asArr?).getD #[]
    for (scenario, scenarioIdx) in scenarios.zipIdx do
      let kind := ((scenario.getStr? "type").getD "scenario").toLower
      if kind == "scenario" || kind == "scenario_outline" then
        let sid := match scenario.get? "id" with
          | some (.str s) => s
          | some other@(.int _) => clojureStr other
          | _ => s!"{fid}__scenario_{scenarioIdx + 1}_{slug ((scenario.getStr? "name").getD "scenario")}"
        let sname := (scenario.getStr? "name").getD "scenario"
        let steps := (scenario.get? "steps" >>= J.asArr?).getD #[]
        let stepId (index : Nat) := s!"evt:{slug sid}__step_{pad3 (index + 1)}"
        for (step, stepIdx) in steps.zipIdx do
          let status := (((step.get? "result" >>= (·.getStr? "status")).getD "unknown")).toLower
          let duration ← match stepDuration step with | .ok n => pure n | .error m => failWith m
          records := records.push (.obj #[
            ("record_kind", .str "cucumber_step"), ("feature", .str featureName), ("feature_id", .str fid),
            ("scenario", .str sname), ("scenario_id", .str sid), ("step", .str ((step.getStr? "name").getD "")),
            ("step_keyword", .str (jtrim ((step.getStr? "keyword").getD ""))), ("step_index", .int (stepIdx + 1)),
            ("status", .str status), ("duration_ns", .int duration), ("event_id", .str (stepId stepIdx)),
            ("actor", .str sid), ("vector_clock", .obj #[(sid, .int (stepIdx + 1))]),
            ("before", .arr (if stepIdx > 0 then #[.str (stepId (stepIdx - 1))] else #[])), ("uri", .str uri)])
  return records

/-- Read one datasource once. -/
def readRecords (spec : Datasource) : IO (Array J) :=
  match spec.type with
  | "file" => readFileSource spec
  | "command" => readCommandSource spec
  | "rest" => readRestSource spec
  | "cucumber" => readCucumberSource spec
  | other => failWith s!"No adapter registered for datasource type {other}; supported: cucumber, command, file, rest"

/-! ## Records to facts -/

structure Fact where
  object : String
  relation : String
  subject : String
  attrs : Array (String × J)
  event : String
  revision : Int
  deriving Inhabited

structure Edge where
  left : String
  right : String
  deriving BEq, Inhabited

/-- `zil.runtime.datascript/normalize-vector-clock`: counters as integers, actors as text. -/
def normalizeVectorClock (clock : J) : Except String (Array (String × Int)) :=
  match clock with
  | .obj fields => fields.mapM fun (actor, counter) =>
      match counter with
      | .int n => .ok (actor, n)
      | .number t =>
          let whole := (t.splitOn ".")[0]!.splitOn "e" |>.head!
          match whole.toInt? with
          | some n => .ok (actor, n)
          | none => .error s!"Vector clock counter must be numeric: {t}"
      | .str s => match (jtrim s).toInt? with
          | some n => .ok (actor, n)
          | none => .error s!"For input string: \"{jtrim s}\""
      | other => .error s!"Vector clock counter must be numeric: {prStr other}"
  | _ => .error "Vector clock must be a map"

private def counterOf (clock : Array (String × Int)) (actor : String) : Int :=
  ((clock.find? (·.1 == actor)).map (·.2)).getD 0

/-- Left happens before right: no counter is greater and some counter is smaller. -/
def vectorClockBefore (left right : Array (String × Int)) : Bool :=
  let actors := (left.map (·.1) ++ right.map (·.1)).foldl (fun acc a => if acc.contains a then acc else acc.push a) #[]
  actors.all (fun a => counterOf left a ≤ counterOf right a) && actors.any (fun a => counterOf left a < counterOf right a)

def vectorClockConcurrent (left right : Array (String × Int)) : Bool :=
  !vectorClockBefore left right && !vectorClockBefore right left

/-- The edges between distinct events whose clocks are ordered. -/
def deriveBeforeEdges (events : Array (String × Array (String × Int))) : Array Edge := Id.run do
  let mut edges : Array Edge := #[]
  for (left, leftClock) in events do
    for (right, rightClock) in events do
      if left != right && vectorClockBefore leftClock rightClock then
        let edge : Edge := { left, right }
        unless edges.contains edge do edges := edges.push edge
  return edges

def subjectValue : J → String
  | .str v => if v.contains ':' || v.startsWith "?" then v else "value:" ++ v
  | .number t => "value:" ++ javaNumber t
  | .int n => "value:" ++ toString n
  | .bool b => "value:" ++ toString b
  | .null => "value:nil"
  | other => "value:" ++ prStr other

private def metricId (value : J) : String :=
  let s := clojureStr value
  if s.contains ':' then s else "metric:" ++ s

private def normalizeEventId (value : J) : Option String :=
  let text? := match value with | .null => none | .str s => some (jtrim s) | other => some (jtrim (clojureStr other))
  text?.bind fun s => if s.toList.all isJavaWs then none else some (if s.contains ':' then s else "event:" ++ s)

private def eventKeyword (eid : String) : String :=
  String.ofList (eid.toList.map fun c => if (c.isAlphanum && c.toNat < 128) || c == '_' || c == ':' || c == '-' || c == '.' then c else '_')

private def eventIdOf (record : J) : Option String :=
  ["event_id", "event-id", "event"].findSome? fun key => record.get? key >>= normalizeEventId

private def truthy : Option J → Bool
  | none | some .null | some (.bool false) => false
  | _ => true

private def excluded : List String := ["metric", "value", "metrics", "before", "vector_clock", "event_id", "event-id"]

/-- The facts one record stands for. -/
def recordFacts (datasourceId : String) (record : J) (ts : Int) : Except String (Array (String × String × String × Array (String × J) × Option String)) := do
  let record := match record with | .obj _ => record | other => .obj #[("value", other)]
  let fields := match record with | .obj fields => fields | _ => #[]
  let event := (eventIdOf record).map eventKeyword
  let tsAttr := ("ingest_ts", J.int ts)
  let mut facts : Array (String × String × String × Array (String × J) × Option String) := #[]
  facts := facts.push (datasourceId, "ingested_record", "value:record", #[tsAttr, ("payload", record)], event)
  -- metric observations
  if truthy (record.get? "metric") && (record.get? "value").isSome then
    facts := facts.push (metricId (record.get? "metric").get!, "observed_from", datasourceId,
      #[("value", (record.get? "value").get!), tsAttr], event)
  else
    match record.get? "metrics" with
    | some (.obj metrics) =>
        for (key, value) in metrics do
          facts := facts.push (metricId (.str key), "observed_from", datasourceId, #[("value", value), tsAttr], event)
    | _ => pure ()
  -- vector clock components
  match record.get? "vector_clock" with
  | some clock@(.obj _) =>
      let normalized ← normalizeVectorClock clock
      if let some eid := eventIdOf record then
        for (actor, counter) in normalized do
          facts := facts.push (eid, "vc_component", "actor:" ++ actor, #[("counter", .int counter), tsAttr], event)
  | _ => pure ()
  -- scalar fields
  for (key, value) in fields do
    unless excluded.contains key do
      facts := facts.push (datasourceId, key, subjectValue value, #[tsAttr], event)
  return facts

/-- Explicit `before` edges of a record and its event's vector clock. -/
def recordCausality (record : J) : Except String (Array Edge × Option (String × Array (String × Int))) := do
  let record := match record with | .obj _ => record | other => .obj #[("value", other)]
  let event := (eventIdOf record).map eventKeyword
  let explicit : Array Edge :=
    match event, record.get? "before" with
    | some right, some (.arr lefts) =>
        lefts.filterMap fun left => (normalizeEventId left).map fun l => { left := eventKeyword l, right }
    | some right, none => #[]
    | _, _ => #[]
  let clock ← match event, record.get? "vector_clock" with
    | some e, some c@(.obj _) => do pure (some (e, ← normalizeVectorClock c))
    | _, _ => pure none
  return (explicit, clock)

/-! ## One ingest run -/

structure SourceResult where
  datasource : String
  type : String
  records : Nat
  facts : Array Fact
  edges : Array Edge
  explicit : Nat
  derived : Nat

/-- Facts, edges and counts of a run over one source. -/
def ingestOnce (spec : Datasource) (revision : Int) (timestamp : Int) (event : Option String := none) :
    IO SourceResult := do
  let records ← readRecords spec
  let defaultEvent := event.getD ("ingest_" ++ spec.id.replace ":" "_")
  let mut facts : Array Fact := #[]
  let mut explicit : Array Edge := #[]
  let mut explicitCount := 0
  let mut clocks : Array (String × Array (String × Int)) := #[]
  for record in records do
    let produced ← match recordFacts spec.id record timestamp with | .ok f => pure f | .error m => failWith m
    for (object, relation, subject, attrs, eventKey) in produced do
      facts := facts.push { object, relation, subject, attrs, event := eventKey.getD defaultEvent, revision }
    let (edges, clock) ← match recordCausality record with | .ok r => pure r | .error m => failWith m
    explicitCount := explicitCount + edges.size
    for edge in edges do
      unless explicit.contains edge do explicit := explicit.push edge
    if let some c := clock then clocks := clocks.push c
  let derived := deriveBeforeEdges clocks
  let all := derived.foldl (init := explicit) fun acc edge => if acc.contains edge then acc else acc.push edge
  return { datasource := spec.id, type := spec.type, records := records.size, facts, edges := all,
           explicit := explicitCount, derived := derived.size }

/-! ## Output -/

def factJson (fact : Fact) : J :=
  .obj #[("object", .str fact.object), ("relation", .str fact.relation), ("subject", .str fact.subject),
    ("attrs", .obj fact.attrs), ("revision", .int fact.revision), ("event", .str fact.event), ("op", .str "assert")]

def sourceJson (result : SourceResult) : J :=
  .obj #[("datasource", .str result.datasource), ("type", .str result.type), ("records", .int result.records),
    ("facts", .int result.facts.size), ("before_edges", .int result.edges.size),
    ("before_edges_explicit", .int result.explicit), ("before_edges_derived", .int result.derived)]

/-- The whole run as one document. -/
def runJson (results : Array SourceResult) : J :=
  .obj #[("schema", .str "ZIL-INGEST/1"), ("sources", .int results.size),
    ("records", .int (results.foldl (· + ·.records) 0)), ("facts", .int (results.foldl (· + ·.facts.size) 0)),
    ("by_source", .arr (results.map sourceJson)),
    ("fact_list", .arr (results.foldl (fun acc r => acc ++ r.facts.map factJson) #[])),
    ("before_edge_list", .arr ((results.foldl (init := (#[] : Array Edge)) fun acc r =>
      r.edges.foldl (fun acc e => if acc.contains e then acc else acc.push e) acc).map fun e =>
        .obj #[("left", .str e.left), ("right", .str e.right)]))]

private def tokenChar (c : Char) : Bool := (c.isAlphanum && c.toNat < 128) || c == '_' || c == ':' || c == '.' || c == '-' || c == '/'

/-- A fact term as ZIL source: bare when it is plain, double-quoted otherwise. -/
def zcToken (value : String) : String :=
  let segments := (value.split fun c => c == ':' || c == '/' || c == '.').toList
  if !value.isEmpty && value.all tokenChar && segments.all (fun segment => !segment.isEmpty) then value
  else "\"" ++ (value.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n" |>.replace "\r" "\\r" |>.replace "\t" "\\t") ++ "\""

private def zcName (value : String) : String :=
  let cleaned := String.ofList (value.toList.map fun c => if (c.isAlphanum && c.toNat < 128) || c == '_' then c else '_')
  if cleaned.isEmpty then "value" else if cleaned.toList.head!.isDigit then "r_" ++ cleaned else cleaned

private def zcAttrValue : J → String
  | .int n => toString n
  | .number t => javaNumber t
  | .bool b => toString b
  | .null => "\"null\""
  | .str s => zcToken' s
  | other => zcToken' (write other)
where
  zcToken' (s : String) : String :=
    "\"" ++ (s.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n" |>.replace "\r" "\\r" |>.replace "\t" "\\t") ++ "\""

/-- The facts as ZIL source. Revision and event are not part of a ZIL fact; the JSON and revision-log outputs carry them. -/
def renderZc (moduleName : String) (facts : Array Fact) : String :=
  let lines := facts.toList.map fun fact =>
    let attrs := if fact.attrs.isEmpty then "" else
      " [" ++ ", ".intercalate (fact.attrs.toList.map fun (k, v) => zcName k ++ "=" ++ zcAttrValue v) ++ "]"
    zcToken fact.object ++ "#" ++ zcName fact.relation ++ "@" ++ zcToken fact.subject ++ attrs ++ "."
  s!"MODULE {moduleName}.\n\n" ++ "\n".intercalate lines ++ (if lines.isEmpty then "" else "\n")

/-! ## Revision log -/

private def attrValueOf : J → Zil.AttrValue
  | .int n => .integer n
  | .number t => .decimal (javaNumber t)
  | .bool b => .boolean b
  | .str s => .text s
  | .null => .text "null"
  | other => .text (write other)

/-- The facts and edges of a run as a revision store: the log `bin/zil snapshot` and `causal-check` read. A fact written twice
at one revision keeps its last attributes; an edge that names an event with no fact is left out and counted. -/
def toRevisionStore (moduleName : String) (results : Array SourceResult) : Except String (Zil.RevisionStore × Nat) := do
  let mut records : Array Zil.RevisionedFact := #[]
  let mut edges : Array Zil.CausalEdge := #[]
  let mut dropped := 0
  for result in results do
    for fact in result.facts do
      let subject ← Zil.Parser.termFromToken (zcToken fact.object)
      let object ← Zil.Parser.termFromToken (zcToken fact.subject)
      let relation ← Zil.Parser.relationNameFromToken (zcName fact.relation)
      let attrs := fact.attrs.map fun (key, value) =>
        ({ key := Lean.Name.mkSimple (zcName key), value := attrValueOf value } : Zil.Attribute)
      unless 0 ≤ fact.revision do throw s!"revision {fact.revision} is negative"
      let record : Zil.RevisionedFact := {
        fact := Zil.RelExpr.mkWithAttrs subject relation object attrs
        revision := fact.revision.toNat
        event := Zil.Codec.nameFromString fact.event }
      match records.findIdx? (fun existing => existing.revision == record.revision && existing.key == record.key) with
      | some index => records := records.set! index record
      | none => records := records.push record
  let events := records.foldl (init := (#[] : Array Lean.Name)) fun acc record =>
    if acc.contains record.event then acc else acc.push record.event
  for result in results do
    for edge in result.edges do
      let left := Zil.Codec.nameFromString edge.left
      let right := Zil.Codec.nameFromString edge.right
      if events.contains left && events.contains right then
        let entry : Zil.CausalEdge := { left, right }
        unless edges.contains entry do edges := edges.push entry
      else dropped := dropped + 1
  let store : Zil.RevisionStore := { moduleName := Zil.Codec.nameFromString moduleName, records, causal := { edges } }
  unless store.valid do throw "the ingested facts and edges do not form a valid revision store (is the causal order cyclic?)"
  return (store, dropped)

end Zil.Runtime.Ingest
