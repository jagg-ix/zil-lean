import Zil.Parser.DeclarationProgram
import Zil.Json.Ordered

/-!
# LTS exporters: TLA+ and Lean 4 skeletons

`LTS_ATOM` declarations describe labelled transition systems. These exporters turn each one into a TLA+ module of
constants (states, initial state, transitions, effects and a canonical trace) that parses with SANY, or into a Lean 4
skeleton (an inductive for the states, one for the events, and a total step function).
-/

namespace Zil.Export

open Zil.Json
open Lean (Name)

/-! ## Names -/

/-- Words of an identifier: camel-case and acronym boundaries and every non-alphanumeric run separate words. -/
def tokenizeIdent (text : String) : List String := Id.run do
  let chars := text.toList.toArray
  -- ([A-Z]+)([A-Z][a-z]) -> $1_$2 : in an uppercase run followed by a lowercase letter, split before the last capital
  let mut step1 : Array Char := #[]
  let mut i := 0
  while i < chars.size do
    if chars[i]!.isUpper then
      let mut j := i
      while j < chars.size && chars[j]!.isUpper do j := j + 1
      let runLength := j - i
      if runLength ≥ 2 && j < chars.size && chars[j]!.isLower then
        for k in [i:j - 1] do step1 := step1.push chars[k]!
        step1 := step1.push '_'
        step1 := step1.push chars[j - 1]!
      else
        for k in [i:j] do step1 := step1.push chars[k]!
      i := j
    else
      step1 := step1.push chars[i]!
      i := i + 1
  -- ([a-z0-9])([A-Z]) -> $1_$2
  let mut step2 : Array Char := #[]
  for k in [0:step1.size] do
    step2 := step2.push step1[k]!
    if (step1[k]!.isLower || step1[k]!.isDigit) && ((step1[k + 1]?.map Char.isUpper).getD false) then step2 := step2.push '_'
  -- split on runs of non-alphanumerics
  let mut parts : Array String := #[]
  let mut current := ""
  for c in step2.toList do
    if c.isAlphanum && c.toNat < 128 then current := current.push c
    else
      unless current.isEmpty do parts := parts.push current
      current := ""
  unless current.isEmpty do parts := parts.push current
  return parts.toList

private def capitalize (lower : String) : String :=
  match lower.toList with
  | [] => ""
  | c :: rest => String.ofList (c.toUpper :: rest)

private def acronyms : List String := ["api", "db", "fsm", "id", "ip", "l3", "ssh", "tcp", "tls", "udp", "ui", "vpn", "ws", "x11"]

/-- A word the way the TLA+ exporter capitalizes it. -/
private def pascalizeTla (part : String) : String :=
  let lower := part.toLower
  if part.all Char.isWhitespace then ""
  else if acronyms.contains lower then lower.toUpper
  else if part.all Char.isDigit then part
  else
    match part.toList with
    | first :: rest => if first.isUpper && rest.all (fun c => c.isAlphanum) then part else capitalize lower
    | [] => ""

/-- A word the way the Lean exporter capitalizes it. -/
private def pascalizeLean (part : String) : String := capitalize part.toLower

def toPascalCase (text : String) : String :=
  match tokenizeIdent text with
  | [] => "Actor"
  | parts => String.join (parts.map pascalizeTla)

def toLowerCamelCase (text : String) : String :=
  match tokenizeIdent text with
  | [] => "actor"
  | head :: tail => head.toLower ++ String.join (tail.map pascalizeTla)

/-- A module identifier: other characters become `_`, a leading digit gets an `M_` prefix. -/
def sanitizeModuleId (text : Option String) : String :=
  let cleaned := String.ofList ((text.getD "ZilLTSBridge").toList.map fun c => if c.isAlphanum && c.toNat < 128 || c == '_' then c else '_')
  if cleaned.toList.head?.map Char.isDigit |>.getD false then "M_" ++ cleaned else cleaned

private def tlaString (s : String) : String :=
  "\"" ++ (s.replace "\\" "\\\\").replace "\"" "\\\"" ++ "\""

/-! ## Vocabulary -/

structure Transition where
  from_ : String
  label : String
  to : String
  effect : Option String := none
  deriving BEq

structure Actor where
  file : String
  module : String
  name : String
  actorPrefix : String
  actorKey : String
  states : Array String
  initial : String
  transitions : Array Transition
  traceLabels : Array String

private def transitionKey (t : Transition) : List String := [t.from_, t.label, t.to, t.effect.getD ""]

private def keyLess (a b : List String) : Bool :=
  let rec go : List String → List String → Bool
    | [], [] => false
    | [], _ => true
    | _, [] => false
    | x :: xs, y :: ys => match compareKeys x y with | .lt => true | .gt => false | .eq => go xs ys
  go a b

private def sortTransitions (ts : Array Transition) : Array Transition :=
  ts.qsort fun a b => keyLess (transitionKey a) (transitionKey b)

/-- Follow the first unused edge from the initial state, as a canonical trace skeleton. -/
def walkTraceSkeleton (initial : String) (transitions : Array Transition) : Array String := Id.run do
  let edges := sortTransitions transitions
  let maxSteps := max 1 (2 * edges.size)
  let mut current := initial
  let mut used : Array (String × String × String) := #[]
  let mut steps : Array String := #[]
  let mut n := 0
  while n < maxSteps && !edges.isEmpty do
    let out := edges.filter (·.from_ == current)
    let candidate := (out.find? fun t => !used.contains (t.from_, t.label, t.to)).orElse fun _ => out[0]?
    match candidate with
    | none => return steps
    | some c =>
        current := c.to
        used := used.push (c.from_, c.label, c.to)
        steps := steps.push c.label
        n := n + 1
  return steps

private def tokenOf (value : Zil.DeclValue) : Option String := value.token?

private def normalizeActor (file module : String) (declaration : Zil.Declaration) : Actor :=
  let attr (key : Name) : Option Zil.DeclValue := (declaration.attr? key).map (·.value)
  let actorId := ((attr `actor).bind tokenOf).getD declaration.name.toString
  let actorKey := ((attr `actor_key).bind tokenOf).getD (toLowerCamelCase actorId)
  let actorPrefix := sanitizeModuleId (some (toPascalCase actorId))
  let states := ((attr `states).map (·.members.filterMap tokenOf)).getD #[]
  let states := (states.qsort fun a b => compareKeys a b == .lt).foldl (fun out s => if out.back? == some s then out else out.push s) #[]
  let initial := ((attr `initial).bind tokenOf).getD ""
  let transitions := match attr `transitions with
    | some (.map entries) =>
        entries.filterMap fun entry =>
          match entry.1, entry.2 with
          | .list key, .list target =>
              match key[0]?.bind tokenOf, key[1]?.bind tokenOf, target[0]?.bind tokenOf with
              | some f, some l, some t => some { from_ := f, label := l, to := t, effect := target[1]?.bind tokenOf : Transition }
              | _, _, _ => none
          | _, _ => none
    | _ => #[]
  let transitions := sortTransitions transitions
  { file, module, name := declaration.name.toString, actorPrefix, actorKey, states, initial, transitions,
    traceLabels := walkTraceSkeleton initial transitions }

structure Vocabulary where
  files : Array String
  modules : Array String
  actors : Array Actor

/-- `.zc` files of a file or directory, sorted by path. -/
partial def collectZcFiles (path : System.FilePath) : IO (Array String) := do
  if !(← path.pathExists) then return #[]
  if ← path.isDir then
    let rec walk (dir : System.FilePath) : IO (Array String) := do
      let mut out := #[]
      for entry in ← dir.readDir do
        if ← entry.path.isDir then out := out ++ (← walk entry.path)
        else if entry.path.toString.endsWith ".zc" then out := out.push entry.path.toString
      return out
    return (← walk path).qsort fun a b => compareKeys a b == .lt
  else return if path.toString.endsWith ".zc" then #[path.toString] else #[]

/-- The text of the first `MODULE <name>.` line, as written. -/
private def rawModuleText (source : String) : Option String :=
  source.splitOn "\n" |>.findSome? fun raw =>
    let line := raw.trim
    if line.startsWith "MODULE " && line.endsWith "." then some ((line.drop 7).dropRight 1 |>.trim.toString) else none

def collectLtsVocabulary (path : System.FilePath) : IO Vocabulary := do
  let files ← collectZcFiles path
  if files.isEmpty then throw (IO.userError s!"No .zc files found in path ({path})")
  let mut actors : Array Actor := #[]
  let mut modules : Array String := #[]
  for file in files do
    let source ← IO.FS.readFile file
    let program ← match Zil.Parser.DeclarationProgram.parseText source with
      | .ok p => pure p
      | .error error => throw (IO.userError s!"Failed to parse .zc file for vocabulary export ({file}): {error.message}")
    let some parsedName := program.moduleName | throw (IO.userError s!"Program must define MODULE <name> for TLA export ({file})")
    -- The parsed `Name` renames a digit-leading component; the exporters want the module as written.
    let module := (rawModuleText source).getD parsedName.toString
    unless modules.contains module do modules := modules.push module
    for declaration in program.declarations do
      if declaration.kind == .ltsAtom then actors := actors.push (normalizeActor file module declaration)
  if actors.isEmpty then throw (IO.userError s!"No LTS_ATOM declarations found ({path})")
  return { files, modules := modules.qsort (fun a b => compareKeys a b == .lt), actors }

/-! ## TLA+ -/

private def renderStringSet (values : Array String) : String :=
  if values.isEmpty then "{}" else "{\n" ++ ",\n".intercalate (values.toList.map fun v => "  " ++ tlaString v) ++ "\n}"

private def renderTransitionSet (rows : Array Transition) : String :=
  if rows.isEmpty then "{}"
  else "{\n" ++ ",\n".intercalate (rows.toList.map fun t =>
    s!"  << {tlaString t.from_}, {tlaString t.label}, {tlaString t.to} >>") ++ "\n}"

private def renderEffectSet (rows : Array Transition) : Option String :=
  let withEffect := rows.filter (·.effect.isSome)
  if withEffect.isEmpty then none
  else some ("{\n" ++ ",\n".intercalate (withEffect.toList.map fun t =>
    s!"  << {tlaString t.from_}, {tlaString t.label}, {tlaString t.to}, {tlaString (t.effect.getD "")} >>") ++ "\n}")

private def renderTraceSeq (actorKey : String) (labels : Array String) : String :=
  if labels.isEmpty then "<< >>"
  else "<<\n" ++ ",\n".intercalate (labels.toList.map fun l => s!"  << {tlaString actorKey}, {tlaString l} >>") ++ "\n>>"

private def renderSystemTrace (actors : Array Actor) : String :=
  let rows := actors.toList.flatMap fun a => a.traceLabels.toList.map fun l => (a.actorKey, l)
  if rows.isEmpty then "<< >>"
  else "<<\n" ++ ",\n".intercalate (rows.map fun (k, l) => s!"  << {tlaString k}, {tlaString l} >>") ++ "\n>>"

private def renderActorBlock (a : Actor) : String :=
  a.actorPrefix ++ "States == " ++ renderStringSet a.states ++ "\n\n" ++
  a.actorPrefix ++ "Initial == " ++ tlaString a.initial ++ "\n\n" ++
  a.actorPrefix ++ "Transitions == " ++ renderTransitionSet a.transitions ++ "\n\n" ++
  (match renderEffectSet a.transitions with
   | some effects => a.actorPrefix ++ "TransitionEffects == " ++ effects ++ "\n\n"
   | none => "") ++
  a.actorPrefix ++ "CanonicalTrace == " ++ renderTraceSeq a.actorKey a.traceLabels ++ "\n"

private def sortActors (actors : Array Actor) : Array Actor :=
  actors.qsort fun a b => compareKeys a.actorPrefix b.actorPrefix == .lt

/-- TLA+ module text for the actors. -/
def renderTlaModule (moduleName : String) (actors : Array Actor) (includeSystemTrace : Bool := true) : Except String String := do
  let prefixes := actors.map (·.actorPrefix)
  let duplicates := (prefixes.toList.filter fun p => (prefixes.toList.filter (· == p)).length > 1).eraseDups
  unless duplicates.isEmpty do throw s!"Duplicate actor prefixes detected while rendering TLA module. {duplicates}"
  let sorted := sortActors actors
  return "---------------------------- MODULE " ++ sanitizeModuleId (some moduleName) ++ " -----------------------------\n" ++
    "(*\nGenerated by `zilInterop export-tla` from ZIL LTS_ATOM declarations.\n*)\n\n" ++
    "EXTENDS Sequences, FiniteSets, TLC\n\n" ++
    "\n".intercalate (sorted.toList.map renderActorBlock) ++
    (if includeSystemTrace then "\nCanonicalSystemTrace == " ++ renderSystemTrace sorted ++ "\n" else "") ++
    "\n=============================================================================\n"

structure TlaExport where
  text : String
  moduleName : String
  vocabulary : Vocabulary

def exportTla (path : System.FilePath) (moduleName : Option String := none) (includeSystemTrace : Bool := true) : IO TlaExport := do
  let vocabulary ← collectLtsVocabulary path
  let name := sanitizeModuleId (some (moduleName.getD (if vocabulary.modules.size == 1 then vocabulary.modules[0]! ++ "_LTSBridge" else "ZilLTSBridge")))
  match renderTlaModule name vocabulary.actors includeSystemTrace with
  | .ok text => return { text, moduleName := name, vocabulary }
  | .error message => throw (IO.userError message)

/-! ## Lean 4 skeleton -/

private def leanReserved : List String :=
  ["abbrev", "axiom", "class", "def", "deriving", "do", "else", "end", "example", "if", "import", "in", "inductive",
   "instance", "let", "match", "namespace", "open", "private", "protected", "set_option", "structure", "theorem",
   "variable", "where", "with"]

private def toPascalIdent (text : String) : String :=
  match tokenizeIdent text with
  | [] => "Item"
  | parts => String.join (parts.map pascalizeLean)

private def toLowerIdent (text : String) : String :=
  match tokenizeIdent text with
  | [] => "item"
  | head :: tail => head.toLower ++ String.join (tail.map pascalizeLean)

private def sanitizeLeanIdent (candidate fallbackPrefix : String) : String :=
  let clean := String.ofList (candidate.toList.map fun c => if c.isAlphanum && c.toNat < 128 || c == '_' then c else '_')
  let withPrefix := if clean.toList.head?.map Char.isDigit |>.getD false then fallbackPrefix ++ clean else clean
  let safe := if leanReserved.contains withPrefix then withPrefix ++ "_" else withPrefix
  if safe.all Char.isWhitespace then fallbackPrefix ++ "item" else safe

/-- Distinct Lean identifiers for the tokens, suffixed `_1`, `_2`, ... on collision. -/
private def uniqueIdentMap (tokens : Array String) (baseFn : String → String) (fallbackPrefix : String) : Array (String × String) := Id.run do
  let mut used : Array String := #[]
  let mut out : Array (String × String) := #[]
  for token in tokens do
    let base := sanitizeLeanIdent (baseFn token) fallbackPrefix
    let mut candidate := base
    let mut index := 1
    while used.contains candidate do
      candidate := s!"{base}_{index}"
      index := index + 1
    used := used.push candidate
    out := out.push (token, candidate)
  return out

private def renderMappingComment (title : String) (mapping : Array (String × String)) : String :=
  let sorted := mapping.qsort fun a b => compareKeys a.1 b.1 == .lt
  s!"/- {title} mapping (source -> Lean constructor)\n" ++ "\n".intercalate (sorted.toList.map fun (s, c) => s!"- {s} -> {c}") ++ "\n-/\n"

private def renderInductive (typeName : String) (ctors : Array String) : String :=
  s!"inductive {typeName} where\n" ++ "\n".intercalate (ctors.toList.map fun c => s!"  | {c}") ++ "\n  deriving DecidableEq, Repr\n"

private def renderList (ctors : Array String) : String :=
  if ctors.isEmpty then "[]" else "[" ++ ", ".intercalate (ctors.toList.map fun c => "." ++ c) ++ "]"

private def lookupOr (map : Array (String × String)) (key : String) : String := (map.find? (·.1 == key)).map (·.2) |>.getD ""

private def renderLeanActor (a : Actor) : String :=
  let stateMap := uniqueIdentMap a.states toLowerIdent "s"
  let eventLabels := (a.transitions.map (·.label)).toList.eraseDups.toArray.qsort fun x y => compareKeys x y == .lt
  let eventMap := uniqueIdentMap eventLabels toLowerIdent "e"
  let rows := a.transitions.map fun t => s!"  | .{lookupOr stateMap t.from_}, .{lookupOr eventMap t.label} => .{lookupOr stateMap t.to}"
  s!"/-! ## {a.actorPrefix} -/\n\n" ++
  renderMappingComment (a.actorPrefix ++ "State") stateMap ++ renderInductive (a.actorPrefix ++ "State") (stateMap.map (·.2)) ++ "\n" ++
  renderMappingComment (a.actorPrefix ++ "Event") eventMap ++ renderInductive (a.actorPrefix ++ "Event") (eventMap.map (·.2)) ++ "\n" ++
  s!"def initial{a.actorPrefix}State : {a.actorPrefix}State := .{lookupOr stateMap a.initial}\n\n" ++
  s!"def step{a.actorPrefix} (s : {a.actorPrefix}State) (e : {a.actorPrefix}Event) : {a.actorPrefix}State :=\n" ++
  "  match s, e with\n" ++ "\n".intercalate rows.toList ++ "\n  | _, _ => s\n\n" ++
  s!"def {a.actorPrefix}CanonicalTrace : List {a.actorPrefix}Event := " ++
  renderList (a.traceLabels.map (lookupOr eventMap)) ++ "\n"

private def moduleTokenToSegment (s : String) : String := sanitizeLeanIdent (toPascalIdent s) "N"

private def sanitizeNamespace (ns : String) : String :=
  let segments := (ns.splitOn ".").filter (!·.all Char.isWhitespace) |>.map moduleTokenToSegment
  if segments.isEmpty then "Zil.Generated" else ".".intercalate segments

private def defaultNamespace (modules : Array String) : String :=
  if modules.size == 1 then
    let words := (String.ofList (modules[0]!.toList.map fun c => if c == '.' || c == '_' || c == ':' || c == '-' then ' ' else c)).splitOn " "
    ".".intercalate (["Zil", "Generated"] ++ (words.filter (!·.all Char.isWhitespace)).map moduleTokenToSegment)
  else "Zil.Generated"

structure LeanExport where
  text : String
  namespace_ : String
  vocabulary : Vocabulary

def exportLean (path : System.FilePath) (namespace_ : Option String := none) : IO LeanExport := do
  let vocabulary ← collectLtsVocabulary path
  let ns := sanitizeNamespace (namespace_.getD (defaultNamespace vocabulary.modules))
  let text := "-- Generated by `zilInterop export-lean` from ZIL LTS_ATOM declarations.\n" ++
    s!"-- Source: {path}\n\n" ++ s!"namespace {ns}\n\n" ++
    "\n\n".intercalate ((sortActors vocabulary.actors).toList.map renderLeanActor) ++ s!"\n\nend {ns}\n"
  return { text, namespace_ := ns, vocabulary }

end Zil.Export
