import Zil.Core.Userset

namespace Zil.Parser

/-- A source error reported by the native `.zc` tuple parser. -/
structure ParseError where
  line : Nat
  column : Nat := 1
  message : String
  sourceLine : String := ""
  deriving Repr, Inhabited

namespace ParseError

def render (error : ParseError) : String :=
  s!"line {error.line}:{error.column}: {error.message}" ++
    (if error.sourceLine.isEmpty then "" else s!"\n  {error.sourceLine}")

end ParseError

private def failAt (line : Nat) (text message : String) : Except ParseError α :=
  .error { line, message, sourceLine := text }

private def cleanSegment (previous : Option String) (segment : String) : Except String String := do
  let clean := segment.replace "-" "_"
  if clean.isEmpty then throw "empty name segment"
  let startsWithDigit := match clean.data.head? with
    | some char => char.isDigit
    | none => false
  if startsWithDigit then
    pure ((if previous == some "user" then "u" else "n") ++ clean)
  else
    pure clean

/-- Convert tuple namespace separators into a stable Lean `Name`. -/
def nameFromToken (value : String) : Except String Name := do
  let normalized := value.trim.replace ":" "." |>.replace "/" "."
  let parts := normalized.splitOn "."
  if parts.isEmpty then throw "empty name"
  let mut result := Name.anonymous
  let mut previous : Option String := none
  for part in parts do
    let safe ← cleanSegment previous part
    result := if result == Name.anonymous then Name.mkSimple safe else Name.str result safe
    previous := some safe
  pure result

private def upperFirst (value : String) : String :=
  match value.data with
  | [] => ""
  | head :: tail => String.mk (head.toUpper :: tail)

/-- Normalize relation spellings into the canonical `zil` namespace. -/
def relationNameFromToken (value : String) : Except String Name := do
  let words := value.trim.replace "_" "-" |>.splitOn "-"
  let first ← words.head?.toExcept "empty relation"
  if first.isEmpty then throw "empty relation"
  let tail := words.drop 1 |>.map fun word => upperFirst word.toLower
  let ident := first.toLower ++ String.intercalate "" tail
  pure (Name.str `zil ident)

private def parseDirectOrUserset
    (lineNumber : Nat) (line subjectText : String)
    (object : Term) (relation : Name) : Except ParseError TupleExpr := do
  let subjectParts := subjectText.trim.splitOn "#"
  let source : Source := { frontend := "zc", line := some lineNumber }
  match subjectParts with
  | [subject] =>
      if subject.trim.isEmpty then failAt lineNumber line "empty tuple subject"
      let subjectName ←
        (nameFromToken subject).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      pure { TupleExpr.direct object relation (.ground subjectName) with source }
  | [usersetObject, usersetRelation] =>
      if usersetObject.trim.isEmpty || usersetRelation.trim.isEmpty then
        failAt lineNumber line "invalid userset subject"
      let usersetName ←
        (nameFromToken usersetObject).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      let usersetRelationName ←
        (relationNameFromToken usersetRelation).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      pure { TupleExpr.withUserset object relation ⟨usersetName⟩ usersetRelationName with source }
  | _ => failAt lineNumber line "tuple subjects support at most one userset selector"

/-- Parse one ground tuple fact, including a userset subject. -/
def parseTupleLine (lineNumber : Nat) (sourceLine : String) : Except ParseError TupleExpr := do
  let line := sourceLine.trim
  unless line.endsWith "." do
    throw { line := lineNumber, message := "tuple fact must end with '.'", sourceLine }
  let body := line.dropRight 1 |>.trim
  if body.contains '[' || body.contains ']' then
    throw { line := lineNumber, message := "tuple attributes are not part of the tuple-only parser", sourceLine }
  let atParts := body.splitOn "@"
  let (left, subjectText) ← match atParts with
    | [left, subject] => pure (left, subject)
    | _ => failAt lineNumber sourceLine "tuple fact requires exactly one '@' separator"
  let leftParts := left.splitOn "#"
  let (objectText, relationText) ← match leftParts with
    | [object, relation] => pure (object, relation)
    | _ => failAt lineNumber sourceLine "tuple fact requires one object/relation '#' separator"
  if objectText.trim.isEmpty || relationText.trim.isEmpty then
    throw { line := lineNumber, message := "tuple object and relation must be nonempty", sourceLine }
  let objectName ←
    (nameFromToken objectText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
  let relationName ←
    (relationNameFromToken relationText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
  parseDirectOrUserset lineNumber sourceLine subjectText (.ground objectName) relationName

private def parseModuleLine (lineNumber : Nat) (sourceLine : String) : Except ParseError Name := do
  let line := sourceLine.trim
  unless line.endsWith "." do
    throw { line := lineNumber, message := "MODULE declaration must end with '.'", sourceLine }
  let value := (line.drop 7).dropRight 1 |>.trim
  if value.isEmpty then
    throw { line := lineNumber, message := "MODULE name is empty", sourceLine }
  (nameFromToken value).mapError fun message =>
    { line := lineNumber, message, sourceLine }

/-- Parse optional `MODULE` plus ground tuple facts from `.zc` source text. -/
def parseText (text : String) : Except ParseError TupleProgram := do
  let mut moduleName : Option Name := none
  let mut tuples : Array TupleExpr := #[]
  let mut lineNumber := 0
  for rawLine in text.splitOn "\n" do
    lineNumber := lineNumber + 1
    let line := rawLine.trim
    if line.isEmpty || line.startsWith "//" then
      continue
    if line.startsWith "MODULE " then
      if moduleName.isSome then
        throw { line := lineNumber, message := "duplicate MODULE declaration", sourceLine := rawLine }
      moduleName := some (← parseModuleLine lineNumber rawLine)
    else
      tuples := tuples.push (← parseTupleLine lineNumber rawLine)
  if tuples.isEmpty then
    throw { line := 1, message := "source contains no tuple facts" }
  pure { moduleName, tuples }

/-- Read and parse one `.zc` tuple file. -/
def parseFile (path : String) : IO (Except ParseError TupleProgram) := do
  let text ← IO.FS.readFile path
  pure (parseText text)

private def groundName : Term → Except String Name
  | .node node => pure node.name
  | .var name => throw s!"generated tuple source contains variable {name}"

private def renderEndpoint : Term → String
  | .node node => s!"node({node.name})"
  | .var name => toString name

private def renderRelation (relation : RelExpr) : String :=
  s!"{renderEndpoint relation.subject} ⟶[{relation.relation}] {renderEndpoint relation.object}"

private def renderTupleDefinition (index : Nat) (tuple : TupleExpr) : Except String String := do
  let objectName ← groundName tuple.object
  match tuple.subject with
  | .direct subject =>
      let subjectName ← groundName subject
      pure <| s!"private def sourceTuple{index} : Zil.TupleExpr :=\n" ++
        s!"  Zil.TupleExpr.direct\n    (.ground `{objectName})\n" ++
        s!"    `{tuple.relation}\n    (.ground `{subjectName})"
  | .userset userset =>
      pure <| s!"private def sourceTuple{index} : Zil.TupleExpr :=\n" ++
        s!"  Zil.TupleExpr.withUserset\n    (.ground `{objectName})\n" ++
        s!"    `{tuple.relation}\n    ⟨`{userset.object.name}⟩\n" ++
        s!"    `{userset.relation}"

/-- Render a parsed tuple program as native ZIL Lean source. -/
def renderLeanModule (program : TupleProgram) (namespaceName : Name) : Except String String := do
  let mut tupleDefs : Array String := #[]
  let mut tupleNames : Array String := #[]
  for index in [:program.tuples.size] do
    tupleDefs := tupleDefs.push (← renderTupleDefinition index program.tuples[index]!)
    tupleNames := tupleNames.push s!"sourceTuple{index}"
  let lowered := program.lower
  let facts := lowered.facts.map fun fact => s!"zil_fact\n  {renderRelation fact}"
  let mut rules : Array String := #[]
  for rule in lowered.rules do
    let variables := String.intercalate " " (rule.variables.map fun name => toString name).toList
    let premises := rule.premises.map fun premise => s!"  ({renderRelation premise})"
    rules := rules.push <|
      s!"zil_theorem_rule generated_{rule.name.toString.replace "." "_"}\n" ++
      s!"  {{{variables} : Zil.Node}}\n" ++
      String.intercalate "\n" premises.toList ++ "\n" ++
      s!"  : {renderRelation rule.conclusion}"
  pure <|
    "import Zil\n\n" ++
    s!"namespace {namespaceName}\n\n" ++
    String.intercalate "\n\n" tupleDefs.toList ++ "\n\n" ++
    "def sourceTuples : Array Zil.TupleExpr := #[\n  " ++
    String.intercalate ",\n  " tupleNames.toList ++ "\n]\n\n" ++
    String.intercalate "\n\n" facts.toList ++
    (if rules.isEmpty then "" else "\n\n" ++ String.intercalate "\n\n" rules.toList) ++
    s!"\n\nend {namespaceName}\n"

/-- Default generated namespace derived from `MODULE`, or a stable fallback. -/
def defaultNamespace (program : TupleProgram) : Name :=
  match program.moduleName with
  | some moduleName =>
      (nameFromToken ("Zil.Generated." ++ toString moduleName)).getD `Zil.Generated.TupleInput
  | none => `Zil.Generated.TupleInput

end Zil.Parser
