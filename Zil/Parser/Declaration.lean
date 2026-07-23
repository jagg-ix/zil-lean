import Zil.Core.DeclarationSet
import Zil.Parser.Macro

namespace Zil.Parser.Declaration

private def containsText (value needle : String) : Bool :=
  (value.splitOn needle).length > 1

private def failAt
    (line : Zil.Parser.Macro.ExpandedLine)
    (message : String) : Except ParseError α :=
  .error { line := line.number, message, sourceLine := line.text }

private def splitFirstChar (value : String) (needle : Char) : Option (String × String) :=
  let rec loop (remaining before : List Char) : Option (String × String) :=
    match remaining with
    | [] => none
    | char :: rest =>
        if char == needle then some (String.mk before.reverse, String.mk rest)
        else loop rest (char :: before)
  loop value.data []

private def splitTopLevel
    (value : String)
    (separator : Char)
    (splitWhitespace : Bool := false) : Except String (Array String) :=
  let rec loop
      (remaining : List Char)
      (depth : Nat)
      (inString escaped : Bool)
      (token : String)
      (out : Array String) : Except String (Array String) := do
    match remaining with
    | [] =>
        if inString then throw "unterminated string literal"
        if depth != 0 then throw "unbalanced declaration delimiters"
        let current := token.trim
        if current.isEmpty then pure out else pure (out.push current)
    | char :: rest =>
        if escaped then
          loop rest depth inString false (token.push char) out
        else if inString then
          if char == '\\' then loop rest depth true true (token.push char) out
          else if char == '"' then loop rest depth false false (token.push char) out
          else loop rest depth true false (token.push char) out
        else if char == '"' then
          loop rest depth true false (token.push char) out
        else if char == '(' || char == '[' || char == '{' then
          loop rest (depth + 1) false false (token.push char) out
        else if char == ')' || char == ']' || char == '}' then
          if depth == 0 then throw "unbalanced closing delimiter"
          else loop rest (depth - 1) false false (token.push char) out
        else if depth == 0 &&
            ((splitWhitespace && char.isWhitespace) || (!splitWhitespace && char == separator)) then
          let current := token.trim
          if current.isEmpty then
            loop rest depth false false "" out
          else
            loop rest depth false false "" (out.push current)
        else
          loop rest depth false false (token.push char) out
  loop value.data 0 false false "" #[]

private def parseNamedTerm (token : String) : Except String Term :=
  let clean := if token.startsWith ":" then token.drop 1 else token
  Zil.Parser.termFromToken clean

private partial def parseValue (text : String) : Except String DeclValue := do
  let token := text.trim
  if token.isEmpty then throw "empty declaration value"
  else if token.length >= 2 && token.startsWith "\"" && token.endsWith "\"" then
    pure (.scalar (.text ((token.drop 1).dropRight 1)))
  else if token == "true" then pure (.scalar (.boolean true))
  else if token == "false" then pure (.scalar (.boolean false))
  else if let some integer := token.toInt? then pure (.scalar (.integer integer))
  else if token.startsWith "#{" && token.endsWith "}" then
    let payload := (token.drop 2).dropRight 1
    let entries ← splitTopLevel payload ' ' true
    let mut values : Array DeclValue := #[]
    for entry in entries do values := values.push (← parseValue entry)
    pure (.set values)
  else if token.startsWith "[" && token.endsWith "]" then
    let payload := (token.drop 1).dropRight 1
    let entries ←
      if containsText payload "," then splitTopLevel payload ','
      else splitTopLevel payload ' ' true
    let mut values : Array DeclValue := #[]
    for entry in entries do values := values.push (← parseValue entry)
    pure (.list values)
  else if token.startsWith "{" && token.endsWith "}" then
    let payload := (token.drop 1).dropRight 1
    let entries ← splitTopLevel payload ','
    let mut pairs : Array (DeclValue × DeclValue) := #[]
    for entry in entries do
      let parts ← splitTopLevel entry ' ' true
      unless parts.size == 2 do
        throw s!"map entry requires key and value: {entry}"
      pairs := pairs.push (← parseValue parts[0]!, ← parseValue parts[1]!)
    pure (.map pairs)
  else if token.contains '.' && token.toInt?.isNone then
    pure (.scalar (.decimal token))
  else
    pure (.scalar (.term (← parseNamedTerm token)))

private def parseAttributes
    (line : Zil.Parser.Macro.ExpandedLine)
    (payload : String) : Except ParseError (Array DeclAttribute) := do
  let entries ← (splitTopLevel payload ',').mapError fun message => {
    line := line.number, message, sourceLine := line.text }
  let mut attrs : Array DeclAttribute := #[]
  for entry in entries do
    let (keyText, valueText) ← (splitFirstChar entry '=').toExcept {
      line := line.number
      message := s!"declaration attribute requires key=value: {entry}"
      sourceLine := line.text
    }
    if keyText.trim.isEmpty || valueText.trim.isEmpty then
      throw { line := line.number, message := "empty declaration attribute", sourceLine := line.text }
    let key ← (Zil.Parser.nameFromToken keyText.trim).mapError fun message => {
      line := line.number, message, sourceLine := line.text }
    let value ← (parseValue valueText).mapError fun message => {
      line := line.number, message, sourceLine := line.text }
    attrs := attrs.push { key, value }
  pure attrs

private def declarationKind? (text : String) : Option DeclarationKind :=
  match text.trim.splitOn " " with
  | keyword :: _ => DeclarationKind.ofKeyword? keyword
  | [] => none

/-- True when a source line begins with a supported declaration keyword. -/
def isDeclarationLine (line : Zil.Parser.Macro.ExpandedLine) : Bool :=
  (declarationKind? line.text).isSome

/-- Parse one supported standard-library declaration. -/
def parseLine
    (line : Zil.Parser.Macro.ExpandedLine) : Except ParseError Declaration := do
  let text := line.text.trim
  unless text.endsWith "." do
    throw { line := line.number, message := "declaration must end with '.'", sourceLine := line.text }
  let body := text.dropRight 1 |>.trim
  let (keyword, rest) ← (splitFirstChar body ' ').toExcept {
    line := line.number, message := "declaration requires a name", sourceLine := line.text }
  let kind ← (DeclarationKind.ofKeyword? keyword.trim).toExcept {
    line := line.number, message := s!"unsupported declaration kind {keyword.trim}", sourceLine := line.text }
  let (nameText, attrs) ←
    match splitFirstChar rest '[' with
    | none => pure (rest.trim, #[])
    | some (nameText, attrsTail) =>
        unless attrsTail.trim.endsWith "]" do
          throw { line := line.number, message := "declaration attribute list must end with ']'", sourceLine := line.text }
        pure (nameText.trim, ← parseAttributes line (attrsTail.trim.dropRight 1))
  if nameText.isEmpty then
    throw { line := line.number, message := "declaration name is empty", sourceLine := line.text }
  let name ← (Zil.Parser.nameFromToken nameText).mapError fun message => {
    line := line.number, message, sourceLine := line.text }
  let declaration : Declaration := {
    kind, name, attrs
    source := { frontend := "zc", line := some line.number }
  }
  let problems := declaration.issues
  unless problems.isEmpty do
    let messages := String.intercalate "; " (problems.toList.map (fun issue => issue.message))
    throw { line := line.number, message := messages, sourceLine := line.text }
  pure declaration

/-- Separate and parse declaration lines while retaining all other expanded
statements for the ordinary program parser. -/
def collect
    (lines : Array Zil.Parser.Macro.ExpandedLine) :
    Except ParseError (Array Declaration × Array Zil.Parser.Macro.ExpandedLine) := do
  let mut declarations : Array Declaration := #[]
  let mut payload : Array Zil.Parser.Macro.ExpandedLine := #[]
  for line in lines do
    if isDeclarationLine line then declarations := declarations.push (← parseLine line)
    else payload := payload.push line
  let problems := Zil.DeclarationSet.issues declarations
  unless problems.isEmpty do
    let first := problems[0]!
    throw {
      line := declarations[0]!.source.line.getD 1
      message := first.message
      sourceLine := ""
    }
  pure (declarations, payload)

/-- Render collected non-declaration lines for the existing source parser. -/
def renderPayload (lines : Array Zil.Parser.Macro.ExpandedLine) : String :=
  String.intercalate "\n" (lines.toList.map (fun line => line.text)) ++
    (if lines.isEmpty then "" else "\n")

end Zil.Parser.Declaration
