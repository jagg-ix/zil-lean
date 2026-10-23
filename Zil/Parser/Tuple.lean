module

public import Zil.Core.Userset

@[expose] public section


open Lean (Name)

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

def failAt (line : Nat) (text message : String) : Except ParseError α :=
  .error { line, message, sourceLine := text }

def cleanSegment (previous : Option String) (segment : String) : Except String String := do
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

/-- Split a token at `:`, `/` and `.` outside double quotes. A double-quoted run stays in one segment together with its
quotes, and a backslash inside it escapes the next character (`\n`, `\r` and `\t` decode to the control character).
`none` means a quote or an escape is left open. -/
def splitOutsideQuotes (value : String) : Option (List String) := Id.run do
  let mut segments : Array String := #[]
  let mut current : String := ""
  let mut inQuote := false
  let mut escaped := false
  for char in value.toList do
    if inQuote then
      if escaped then
        let decoded := match char with
          | 'n' => '\n'
          | 'r' => '\r'
          | 't' => '\t'
          | other => other
        current := current.push decoded
        escaped := false
      else if char == '\\' then
        escaped := true
      else if char == '"' then
        current := current.push char
        inQuote := false
      else
        current := current.push char
    else if char == '"' then
      current := current.push char
      inQuote := true
    else if char == ':' || char == '/' || char == '.' then
      segments := segments.push current
      current := ""
    else
      current := current.push char
  if inQuote || escaped then return none
  return some (segments.push current).toList

/-- The name of a token that contains a double quote and that the ordinary rules above reject, usually because a quoted run
holds a separator (a URL has `//`). Quoted runs keep their text exactly and their quotes, as an accepted quoted token
already does (`value:"4456"` is `value.«"4456"»`), so two different strings never share a name. Unquoted segments follow
`cleanSegment`. -/
def quotedNameFromToken (value : String) : Option Name := do
  let parts ← splitOutsideQuotes value
  let mut result := Name.anonymous
  let mut previous : Option String := none
  for part in parts do
    let safe ←
      if part.contains '"' then some part
      else (cleanSegment previous part).toOption
    result := if result == Name.anonymous then Name.mkSimple safe else Name.str result safe
    previous := some safe
  some result

/-- Split `text` at `separator` where it is outside double quotes; the pieces keep their text exactly, quotes and
backslashes included. A backslash inside a quoted run escapes the next character, so `\"` does not end the run. -/
def splitOnOutsideQuotes (separator : Char) (text : String) : List String := Id.run do
  let mut pieces : Array String := #[]
  let mut current : String := ""
  let mut inQuote := false
  let mut escaped := false
  for char in text.toList do
    if inQuote then
      current := current.push char
      if escaped then escaped := false
      else if char == '\\' then escaped := true
      else if char == '"' then inQuote := false
    else if char == '"' then
      current := current.push char
      inQuote := true
    else if char == separator then
      pieces := pieces.push current
      current := ""
    else
      current := current.push char
  return (pieces.push current).toList

/-- `String.splitOn` for a one-character separator, or the same split that ignores separators inside double quotes. The
second is only used to retry a line that the first could not parse. -/
def splitOnQuoteAware (aware : Bool) (separator : String) (text : String) : List String :=
  if aware && separator.length == 1 then splitOnOutsideQuotes (separator.get 0) text
  else text.splitOn separator

/-- Parse a ground token or a `?variable` token. A token that parses today keeps exactly the name it has today; only a
token with a double quote that today is rejected falls back to `quotedNameFromToken`. -/
def termFromToken (value : String) : Except String Term := do
  let token := value.trim
  if token.startsWith "?" then
    let nameText := token.drop 1
    if nameText.isEmpty then throw "empty variable name"
    pure (.variable (← nameFromToken nameText.toString))
  else
    match nameFromToken token with
    | .ok name => pure (.ground name)
    | .error message =>
        match (if token.contains '"' then quotedNameFromToken token else none) with
        | some name => pure (.ground name)
        | none => throw message

def upperFirst (value : String) : String :=
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

def parseAttrValue (value : String) : Except String AttrValue := do
  let token := value.trim
  if token.length >= 2 && token.startsWith "\"" && token.endsWith "\"" then
    pure (.text ((token.drop 1).dropRight 1).toString)
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

def parseAttributes
    (lineNumber : Nat) (sourceLine text : String) (aware : Bool := false) :
    Except ParseError (Array Attribute) := do
  if text.trim.isEmpty then return #[]
  let mut attrs : Array Attribute := #[]
  for rawEntry in splitOnQuoteAware aware "," text do
    let (keyText, valueText) ← match splitOnQuoteAware aware "=" rawEntry with
      | key :: rest@(_ :: _) => pure (key.trim, (String.intercalate "=" rest).trim)
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

def splitTupleAndAttributes
    (lineNumber : Nat) (sourceLine body : String) (aware : Bool := false) :
    Except ParseError (String × Array Attribute) := do
  match splitOnQuoteAware aware "[" body with
  | [tupleText] => pure (tupleText.trim, #[])
  | [tupleText, attrsText] =>
      unless attrsText.trim.endsWith "]" do
        throw { line := lineNumber, message := "attribute list must end with ']'", sourceLine }
      let content := attrsText.trim.dropRight 1
      pure (tupleText.trim, ← parseAttributes lineNumber sourceLine content aware)
  | _ => failAt lineNumber sourceLine "tuple contains more than one attribute list"

def parseDirectOrUserset
    (lineNumber : Nat) (line subjectText : String)
    (object : Term) (relation : Name) (attrs : Array Attribute) (aware : Bool := false) :
    Except ParseError TupleExpr := do
  let subjectParts := splitOnQuoteAware aware "#" subjectText.trim
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

/-- Parse one tuple fact, optionally treating `@`, `#`, `[`, `,` and `=` inside double quotes as text. -/
def parseTupleLineWith (aware : Bool) (lineNumber : Nat) (sourceLine : String) : Except ParseError TupleExpr := do
  let line := sourceLine.trim
  unless line.endsWith "." do
    throw { line := lineNumber, message := "tuple fact must end with '.'", sourceLine }
  let body := line.dropRight 1 |>.trim
  let (tupleText, attrs) ← splitTupleAndAttributes lineNumber sourceLine body aware
  let atParts := splitOnQuoteAware aware "@" tupleText
  let (left, subjectText) ← match atParts with
    | [left, subject] => pure (left, subject)
    | _ => failAt lineNumber sourceLine "tuple fact requires exactly one '@' separator"
  let leftParts := splitOnQuoteAware aware "#" left
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
  let tuple ← parseDirectOrUserset lineNumber sourceLine subjectText object relation attrs aware
  unless tuple.isGround do
    throw { line := lineNumber, message := "top-level tuple facts must be ground", sourceLine }
  pure tuple

/-- Parse one tuple fact, including attributes and a userset subject. A line that parses today parses exactly as it does
today. Only a line with a double quote that today is rejected is retried with separators inside quotes ignored, and if the
retry fails too, today's error is the one reported. -/
def parseTupleLine (lineNumber : Nat) (sourceLine : String) : Except ParseError TupleExpr :=
  match parseTupleLineWith false lineNumber sourceLine with
  | .ok tuple => .ok tuple
  | .error today =>
      if sourceLine.contains '"' then
        match parseTupleLineWith true lineNumber sourceLine with
        | .ok tuple => .ok tuple
        | .error _ => .error today
      else .error today

def parseModuleLine (lineNumber : Nat) (sourceLine : String) : Except ParseError Name := do
  let line := sourceLine.trim
  unless line.endsWith "." do
    throw { line := lineNumber, message := "MODULE declaration must end with '.'", sourceLine }
  let value := (line.drop 7).dropRight 1 |>.trim
  if value.isEmpty then
    throw { line := lineNumber, message := "MODULE name is empty", sourceLine }
  (nameFromToken value.toString).mapError fun message =>
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

def groundName : Term → Except String Name
  | .node node => pure node.name
  | .var name => throw s!"generated tuple source contains variable {name}"

def leanString (value : String) : String :=
  let escaped := value.replace "\\" "\\\\"
    |>.replace "\"" "\\\""
    |>.replace "\n" "\\n"
    |>.replace "\t" "\\t"
  "\"" ++ escaped ++ "\""

/-- A Lean string literal for any text: control characters and quotes are escaped. -/
def leanStringAnyText (value : String) : String :=
  let escaped := value.toList.foldl (init := "") fun out char =>
    out ++ (match char with
      | '\\' => "\\\\"
      | '"' => "\\\""
      | '\n' => "\\n"
      | '\r' => "\\r"
      | '\t' => "\\t"
      | other =>
          if other.val < 32 then
            let hex := Nat.toDigits 16 other.val.toNat
            "\\x" ++ String.ofList (if hex.length < 2 then '0' :: hex else hex)
          else String.singleton other)
  "\"" ++ escaped ++ "\""

/-- A segment that the backtick name literal cannot carry: `«` `»` quoting has no escape for `»`, and a raw control character
would break the line. -/
def segmentNeedsConstructor (segment : String) : Bool :=
  segment.toList.any fun char => char == '»' || char.val < 32

def nameNeedsConstructor : Name → Bool
  | .anonymous => false
  | .str parent segment => segmentNeedsConstructor segment || nameNeedsConstructor parent
  | .num parent _ => nameNeedsConstructor parent

partial def nameConstructor : Name → String
  | .anonymous => "Lean.Name.anonymous"
  | .str parent segment => s!"(Lean.Name.str {nameConstructor parent} {leanStringAnyText segment})"
  | .num parent index => s!"(Lean.Name.num {nameConstructor parent} {index})"

/-- How a ground name is written into generated Lean. Every name that was writable before is written exactly as before
(`` `a.b ``); only a name with a character the literal cannot hold is built from its parts. -/
def leanNameLiteral (name : Name) : String :=
  if nameNeedsConstructor name then nameConstructor name else s!"`{name}"

def renderAttrValue : AttrValue → String
  | .text value => s!".text {leanString value}"
  | .integer value => s!".integer {value}"
  | .decimal value => s!".decimal {leanString value}"
  | .boolean value => if value then ".boolean true" else ".boolean false"
  | .term (.var name) => s!".term (.variable `{name})"
  | .term (.node node) => s!".term (.ground {leanNameLiteral node.name})"

def renderAttributes (attrs : Array Attribute) : String :=
  if attrs.isEmpty then "#[]"
  else
    "#[\n      " ++ String.intercalate ",\n      " (attrs.toList.map fun entry =>
      s!"\{ key := `{entry.key}, value := {renderAttrValue entry.value} }") ++ "\n    ]"

def renderSource (source : Source) : String :=
  let file := match source.file with
    | none => "none"
    | some value => "some " ++ leanString value
  let line := match source.line with
    | none => "none"
    | some value => s!"some {value}"
  s!"\{ frontend := {leanString source.frontend}, file := {file}, line := {line} }"

def renderTupleDefinition (index : Nat) (tuple : TupleExpr) : Except String String := do
  let objectName ← groundName tuple.object
  let base ← match tuple.subject with
    | .direct subject =>
        let subjectName ← groundName subject
        pure <| "Zil.TupleExpr.direct\n" ++
          s!"      (.ground {leanNameLiteral objectName})\n" ++
          s!"      `{tuple.relation}\n" ++
          s!"      (.ground {leanNameLiteral subjectName})"
    | .userset userset =>
        pure <| "Zil.TupleExpr.withUserset\n" ++
          s!"      (.ground {leanNameLiteral objectName})\n" ++
          s!"      `{tuple.relation}\n" ++
          s!"      ⟨`{userset.object.name}⟩\n" ++
          s!"      `{userset.relation}"
  pure <| s!"private def sourceTuple{index} : Zil.TupleExpr :=\n" ++
    "  { " ++ base ++ " with\n" ++
    s!"    attrs := {renderAttributes tuple.attrs}\n" ++
    s!"    source := {renderSource tuple.source} }"

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
    "import Zil.Core.Program\nimport Zil.Syntax.Environment\n\n" ++
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
      (nameFromToken ("Zil.Generated." ++ toString moduleName)).toOption.getD `Zil.Generated.TupleInput
  | none => `Zil.Generated.TupleInput

end Zil.Parser
