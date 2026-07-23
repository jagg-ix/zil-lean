import Zil.Core.Userset

namespace Zil.Parser

/-- A source error reported by the native `.zc` parser. -/
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

/-- Parse a ground token or a `?variable` token. -/
def termFromToken (value : String) : Except String Term := do
  let token := value.trim
  if token.startsWith "?" then
    let nameText := token.drop 1
    if nameText.isEmpty then throw "empty variable name"
    pure (.variable (← nameFromToken nameText))
  else
    pure (.ground (← nameFromToken token))

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

private def parseAttrValue (value : String) : Except String AttrValue := do
  let token := value.trim
  if token.length >= 2 && token.startsWith "\"" && token.endsWith "\"" then
    pure (.text ((token.drop 1).dropRight 1))
  else if token == "true" then
    pure (.boolean true)
  else if token == "false" then
    pure (.boolean false)
  else if let some integer := token.toInt? then
    pure (.integer integer)
  else if token.contains '.' then
    pure (.decimal token)
  else
    pure (.term (← termFromToken token))

private def parseAttributes
    (lineNumber : Nat) (sourceLine text : String) : Except ParseError (Array Attribute) := do
  if text.trim.isEmpty then return #[]
  let mut attrs : Array Attribute := #[]
  for rawEntry in text.splitOn "," do
    let (keyText, valueText) ← match rawEntry.splitOn "=" with
      | [key, value] => pure (key.trim, value.trim)
      | _ => failAt lineNumber sourceLine s!"invalid attribute entry: {rawEntry.trim}"
    if keyText.isEmpty || valueText.isEmpty then
      throw { line := lineNumber, message := "attribute key and value must be nonempty", sourceLine }
    let key ← (nameFromToken keyText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
    let value ← (parseAttrValue valueText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
    attrs := attrs.push { key, value }
  unless Attribute.keysUnique attrs do
    throw { line := lineNumber, message := "duplicate attribute key", sourceLine }
  pure attrs

private def splitTupleAndAttributes
    (lineNumber : Nat) (sourceLine body : String) : Except ParseError (String × Array Attribute) := do
  match body.splitOn "[" with
  | [tupleText] => pure (tupleText.trim, #[])
  | [tupleText, attrsText] =>
      unless attrsText.trim.endsWith "]" do
        throw { line := lineNumber, message := "attribute list must end with ']'", sourceLine }
      let content := attrsText.trim.dropRight 1
      pure (tupleText.trim, ← parseAttributes lineNumber sourceLine content)
  | _ => failAt lineNumber sourceLine "tuple contains more than one attribute list"

private def parseDirectOrUserset
    (lineNumber : Nat) (line subjectText : String)
    (object : Term) (relation : Name) (attrs : Array Attribute) : Except ParseError TupleExpr := do
  let subjectParts := subjectText.trim.splitOn "#"
  let source : Source := { frontend := "zc", line := some lineNumber }
  match subjectParts with
  | [subject] =>
      if subject.trim.isEmpty then failAt lineNumber line "empty tuple subject"
      let subjectTerm ←
        (termFromToken subject).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      pure { TupleExpr.direct object relation subjectTerm attrs with source }
  | [usersetObject, usersetRelation] =>
      if usersetObject.trim.isEmpty || usersetRelation.trim.isEmpty then
        failAt lineNumber line "invalid userset subject"
      let usersetName ←
        (nameFromToken usersetObject).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      let usersetRelationName ←
        (relationNameFromToken usersetRelation).mapError fun message =>
          { line := lineNumber, message, sourceLine := line }
      pure { TupleExpr.withUserset object relation ⟨usersetName⟩ usersetRelationName attrs with source }
  | _ => failAt lineNumber line "tuple subjects support at most one userset selector"

/-- Parse one tuple fact, including attributes and a userset subject. -/
def parseTupleLine (lineNumber : Nat) (sourceLine : String) : Except ParseError TupleExpr := do
  let line := sourceLine.trim
  unless line.endsWith "." do
    throw { line := lineNumber, message := "tuple fact must end with '.'", sourceLine }
  let body := line.dropRight 1 |>.trim
  let (tupleText, attrs) ← splitTupleAndAttributes lineNumber sourceLine body
  let atParts := tupleText.splitOn "@"
  let (left, subjectText) ← match atParts with
    | [left, subject] => pure (left, subject)
    | _ => failAt lineNumber sourceLine "tuple fact requires exactly one '@' separator"
  let leftParts := left.splitOn "#"
  let (objectText, relationText) ← match leftParts with
    | [object, relation] => pure (object, relation)
    | _ => failAt lineNumber sourceLine "tuple fact requires one object/relation '#' separator"
  if objectText.trim.isEmpty || relationText.trim.isEmpty then
    throw { line := lineNumber, message := "tuple object and relation must be nonempty", sourceLine }
  let object ←
    (termFromToken objectText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
  let relation ←
    (relationNameFromToken relationText).mapError fun message =>
      { line := lineNumber, message, sourceLine }
  let tuple ← parseDirectOrUserset lineNumber sourceLine subjectText object relation attrs
  unless tuple.isGround do
    throw { line := lineNumber, message := "top-level tuple facts must be ground", sourceLine }
  pure tuple

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

private def leanString (value : String) : String :=
  let escaped := value.replace "\\" "\\\\"
    |>.replace "\"" "\\\""
    |>.replace "\n" "\\n"
    |>.replace "\t" "\\t"
  "\"" ++ escaped ++ "\""

private def renderAttrValue : AttrValue → String
  | .text value => s!".text {leanString value}"
  | .integer value => s!".integer {value}"
  | .decimal value => s!".decimal {leanString value}"
  | .boolean value => if value then ".boolean true" else ".boolean false"
  | .term (.var name) => s!".term (.variable `{name})"
  | .term (.node node) => s!".term (.ground `{node.name})"

private def renderAttributes (attrs : Array Attribute) : String :=
  if attrs.isEmpty then "#[]"
  else
    "#[\n      " ++ String.intercalate ",\n      " (attrs.toList.map fun entry =>
      s!"{{ key := `{entry.key}, value := {renderAttrValue entry.value} }}") ++ "\n    ]"

private def renderSource (source : Source) : String :=
  let file := match source.file with
    | none => "none"
    | some value => "some " ++ leanString value
  let line := match source.line with
    | none => "none"
    | some value => s!"some {value}"
  s!"{{ frontend := {leanString source.frontend}, file := {file}, line := {line} }}"

private def renderTupleDefinition (index : Nat) (tuple : TupleExpr) : Except String String := do
  let objectName ← groundName tuple.object
  let base ← match tuple.subject with
    | .direct subject =>
        let subjectName ← groundName subject
        pure <| "Zil.TupleExpr.direct\n" ++
          s!"      (.ground `{objectName})\n" ++
          s!"      `{tuple.relation}\n" ++
          s!"      (.ground `{subjectName})"
    | .userset userset =>
        pure <| "Zil.TupleExpr.withUserset\n" ++
          s!"      (.ground `{objectName})\n" ++
          s!"      `{tuple.relation}\n" ++
          s!"      ⟨`{userset.object.name}⟩\n" ++
          s!"      `{userset.relation}"
  pure <| s!"private def sourceTuple{index} : Zil.TupleExpr :=\n" ++
    "  { " ++ base ++ " with\n" ++
    s!"    attrs := {renderAttributes tuple.attrs}\n" ++
    s!"    source := {renderSource tuple.source} }}"

/-- Render a parsed tuple program as native ZIL Lean source. -/
def renderLeanModule (program : TupleProgram) (namespaceName : Name) : Except String String := do
  let mut tupleDefs : Array String := #[]
  let mut tupleNames : Array String := #[]
  let mut registrations : Array String := #[]
  for tuple in program.tuples do
    let index := tupleDefs.size
    tupleDefs := tupleDefs.push (← renderTupleDefinition index tuple)
    tupleNames := tupleNames.push s!"sourceTuple{index}"
    registrations := registrations.push s!"zil_register_tuple sourceTuple{index}"
  pure <|
    "import Zil\n\n" ++
    s!"namespace {namespaceName}\n\n" ++
    String.intercalate "\n\n" tupleDefs.toList ++ "\n\n" ++
    "def sourceTuples : Array Zil.TupleExpr := #[\n  " ++
    String.intercalate ",\n  " tupleNames.toList ++ "\n]\n\n" ++
    String.intercalate "\n" registrations.toList ++
    s!"\n\nend {namespaceName}\n"

/-- Default generated namespace derived from `MODULE`, or a stable fallback. -/
def defaultNamespace (program : TupleProgram) : Name :=
  match program.moduleName with
  | some moduleName =>
      (nameFromToken ("Zil.Generated." ++ toString moduleName)).getD `Zil.Generated.TupleInput
  | none => `Zil.Generated.TupleInput

end Zil.Parser
