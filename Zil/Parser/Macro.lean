import Zil.Core.Macro
import Zil.Parser.Tuple

namespace Zil.Parser.Macro

/-- One source line after macro preprocessing. Generated statements retain the
line number of the `USE` statement and the active expansion stack. -/
structure ExpandedLine where
  number : Nat
  text : String
  stack : Array Name := #[]
  rawStack : Array String := #[]
  deriving Repr, Inhabited

/-- Result of collecting definitions and expanding source-level macro uses. -/
structure Preprocessed where
  macros : Array Zil.MacroDef := #[]
  expansions : Array Zil.MacroExpansion := #[]
  lines : Array ExpandedLine := #[]
  deriving Repr, Inhabited

private def stackSuffix (stack : Array Name) (rawStack : Array String := #[]) : String :=
  if !rawStack.isEmpty then
    " (macro stack: " ++ String.intercalate " -> " rawStack.toList ++ ")"
  else if stack.isEmpty then ""
  else " (macro stack: " ++ String.intercalate " -> " (stack.toList.map toString) ++ ")"

private def lineStackSuffix (line : ExpandedLine) : String :=
  stackSuffix line.stack line.rawStack

private def containsText (value needle : String) : Bool :=
  (value.splitOn needle).length > 1

private def equalsCI (left right : String) : Bool :=
  left.toLower == right.toLower

private def whitespace (char : Char) : Bool :=
  let code := char.toNat
  char == ' ' || (9 <= code && code <= 13)

/-- Consume a control keyword followed by one or more whitespace characters.
This matches the source grammar's `\\s+` separator while preserving the
original token text that follows it. -/
private def keywordRemainder? (value keyword : String) : Option String :=
  let chars := value.toList
  let headText := String.ofList (chars.take keyword.length)
  if !equalsCI headText keyword then none
  else
    match chars.drop keyword.length with
    | first :: rest =>
        if whitespace first then (String.ofList rest).trimAscii.toString else none
    | [] => none

/-- Remove `//` comments outside quoted strings. Escaped quotes and `//` inside a
string are preserved. This is the lexical behavior the macro libraries rely on. -/
private def stripLineComment (value : String) : String :=
  let rec loop
      (remaining : List Char)
      (inString escaped : Bool)
      (out : String) : String :=
    match remaining with
    | [] => out
    | char :: rest =>
        if escaped then
          loop rest inString false (out.push char)
        else if inString then
          if char == '\\' then
            loop rest true true (out.push char)
          else if char == '"' then
            loop rest false false (out.push char)
          else
            loop rest true false (out.push char)
        else if char == '"' then
          loop rest true false (out.push char)
        else
          match rest with
          | next :: _ =>
              if char == '/' && next == '/' then out
              else loop rest false false (out.push char)
          | [] => loop rest false false (out.push char)
  loop value.data false false ""

private def failAt (line : ExpandedLine) (message : String) : Except ParseError α :=
  .error {
    line := line.number
    message := message ++ stackSuffix line.stack
    sourceLine := line.text
  }

private def splitFirstChar (value : String) (needle : Char) : Option (String × String) :=
  let rec loop (remaining before : List Char) : Option (String × String) :=
    match remaining with
    | [] => none
    | char :: rest =>
        if char == needle then
          some (String.mk before.reverse, String.mk rest)
        else
          loop rest (char :: before)
  loop value.data []

/-- Split comma-separated macro parameters or arguments while respecting quoted
strings and nested `()`, `[]`, and `{}` delimiters. -/
private def splitTopLevelComma (value : String) : Except String (Array String) :=
  let rec loop
      (remaining : List Char)
      (depth : Nat)
      (inString escaped : Bool)
      (token : String)
      (out : Array String) : Except String (Array String) := do
    match remaining with
    | [] =>
        if inString then throw "unterminated string literal"
        if depth != 0 then throw "unbalanced macro argument delimiters"
        let final := token.trim
        if final.isEmpty then
          if out.isEmpty then pure #[] else throw "empty macro argument"
        else
          pure (out.push final)
    | char :: rest =>
        if escaped then
          loop rest depth inString false (token.push char) out
        else if inString then
          if char == '\\' then
            loop rest depth true true (token.push char) out
          else if char == '"' then
            loop rest depth false false (token.push char) out
          else
            loop rest depth true false (token.push char) out
        else if char == '"' then
          loop rest depth true false (token.push char) out
        else if char == '(' || char == '[' || char == '{' then
          loop rest (depth + 1) false false (token.push char) out
        else if char == ')' || char == ']' || char == '}' then
          if depth == 0 then throw "unbalanced closing delimiter"
          else loop rest (depth - 1) false false (token.push char) out
        else if char == ',' && depth == 0 then
          let current := token.trim
          if current.isEmpty then throw "empty macro argument"
          else loop rest depth false false "" (out.push current)
        else
          loop rest depth false false (token.push char) out
  loop value.data 0 false false "" #[]

private def sourceLines (text : String) : Array ExpandedLine := Id.run do
  let mut out : Array ExpandedLine := #[]
  let mut number := 0
  for raw in text.splitOn "\n" do
    number := number + 1
    let withoutComment := stripLineComment raw
    let trimmed := withoutComment.trim
    if trimmed.isEmpty then continue
    out := out.push { number, text := trimmed }
  out

private def parseNameAt (line : ExpandedLine) (value : String) : Except ParseError Name :=
  (Zil.Parser.nameFromToken value).mapError fun message => {
    line := line.number
    message := message ++ stackSuffix line.stack
    sourceLine := line.text
  }

private def parseHeader (line : ExpandedLine) : Except ParseError (String × Array String) := do
  let text := line.text.trim
  let some headerText := keywordRemainder? text "MACRO"
    | throw {
        line := line.number
        message := "invalid MACRO header" ++ lineStackSuffix line
        sourceLine := line.text
      }
  unless text.endsWith ":" do
    throw {
      line := line.number
      message := "invalid MACRO header" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let body := (headerText.dropEnd 1).trimAscii.toString
  let (nameText, tail) ← (splitFirstChar body '(').toExcept {
    line := line.number
    message := "MACRO header requires a parameter list" ++ lineStackSuffix line
    sourceLine := line.text
  }
  unless tail.endsWith ")" do
    throw {
      line := line.number
      message := "MACRO parameter list must end with ')'" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let name := nameText.trimAscii.toString
  unless Zil.MacroIdent.validName name do
    throw {
      line := line.number
      message := s!"invalid macro identifier {name}" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let rawParams ← (splitTopLevelComma (tail.dropRight 1)).mapError fun message => {
    line := line.number
    message := message ++ lineStackSuffix line
    sourceLine := line.text
  }
  let mut params : Array String := #[]
  for raw in rawParams do
    let param := raw.trimAscii.toString
    unless Zil.MacroIdent.validParameter param do
      throw {
        line := line.number
        message := s!"invalid macro parameter {param}" ++ lineStackSuffix line
        sourceLine := line.text
      }
    if params.contains param then
      throw {
        line := line.number
        message := s!"duplicate macro parameter {param}" ++ lineStackSuffix line
        sourceLine := line.text
      }
    params := params.push param
  pure (name, params)

private partial def collectBody
    (lines : Array ExpandedLine)
    (index : Nat)
    (header : ExpandedLine)
    (emitted : Array String) : Except ParseError (Nat × Array String) := do
  if index >= lines.size then
    throw {
      line := header.number
      message := "unterminated macro definition; expected ENDMACRO."
      sourceLine := header.text
    }
  let line := lines[index]!
  let text := line.text.trim
  if equalsCI text "ENDMACRO." then
    if emitted.isEmpty then failAt header "macro definition must emit at least one statement"
    else pure (index + 1, emitted)
  else if let some statement := keywordRemainder? text "EMIT" then
    if statement.isEmpty then failAt line "EMIT requires a source statement"
    else collectBody lines (index + 1) header (emitted.push statement)
  else
    failAt line "macro body accepts only EMIT statements and ENDMACRO."

private partial def collectDefinitions
    (lines : Array ExpandedLine)
    (index : Nat)
    (definitions : Array Zil.MacroDef)
    (payload : Array ExpandedLine) : Except ParseError (Array Zil.MacroDef × Array ExpandedLine) := do
  if index >= lines.size then return (definitions, payload)
  let line := lines[index]!
  let text := line.text.trim
  if (keywordRemainder? text "MACRO").isSome then
    let (rawName, rawParameters) ← parseHeader line
    if definitions.any (fun definition => Zil.MacroDef.sourceName definition == rawName) then
      throw {
        line := line.number
        message := s!"duplicate macro definition {rawName}"
        sourceLine := line.text
      }
    let (nextIndex, emit) ← collectBody lines (index + 1) line #[]
    let name ← parseNameAt line rawName
    let mut parameters : Array Name := #[]
    for rawParameter in rawParameters do
      parameters := parameters.push (← parseNameAt line rawParameter)
    let definition : Zil.MacroDef := {
      name, parameters, emit
      rawName := { raw := rawName }
      rawParameters := rawParameters.map fun parameter => { raw := parameter }
      source := { frontend := "zc", line := some line.number }
    }
    unless definition.valid do
      throw {
        line := line.number
        message := s!"invalid macro definition {rawName}"
        sourceLine := line.text
      }
    collectDefinitions lines nextIndex (definitions.push definition) payload
  else if equalsCI text "ENDMACRO." || (keywordRemainder? text "EMIT").isSome then
    failAt line "macro body statement appears outside a MACRO definition"
  else
    collectDefinitions lines (index + 1) definitions (payload.push line)

private def parseUse? (line : ExpandedLine) : Except ParseError (Option (String × Array String)) := do
  let text := line.text.trim
  let useText ← match keywordRemainder? text "USE" with
    | some value => pure value
    | none => return none
  unless text.endsWith "." do
    throw {
      line := line.number
      message := "USE statement must end with '.'" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let body := (useText.dropEnd 1).trimAscii.toString
  let (nameText, tail) ← (splitFirstChar body '(').toExcept {
    line := line.number
    message := "USE requires an argument list" ++ lineStackSuffix line
    sourceLine := line.text
  }
  unless tail.endsWith ")" do
    throw {
      line := line.number
      message := "USE argument list must end with ')'" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let name := nameText.trimAscii.toString
  unless Zil.MacroIdent.validName name do
    throw {
      line := line.number
      message := s!"invalid macro identifier {name}" ++ lineStackSuffix line
      sourceLine := line.text
    }
  let args ← (splitTopLevelComma (tail.dropRight 1)).mapError fun message => {
    line := line.number
    message := message ++ lineStackSuffix line
    sourceLine := line.text
  }
  pure (some (name, args))

private def instantiate
    (line : ExpandedLine)
    (definition : Zil.MacroDef)
    (arguments : Array String) : Except ParseError (Array String) := do
  unless arguments.size == definition.parameters.size do
    throw {
      line := line.number
      message := s!"macro {Zil.MacroDef.sourceName definition} expects {definition.parameters.size} arguments, got {arguments.size}" ++
        lineStackSuffix line
      sourceLine := line.text
    }
  let bindings := Array.zip (Zil.MacroDef.sourceParameters definition) arguments
  let instantiated := definition.emit.map fun statement =>
    bindings.foldl (init := statement) fun current binding =>
      current.replace ("{{" ++ binding.1 ++ "}}") binding.2
  for statement in instantiated do
    if containsText statement "{{" || containsText statement "}}" then
      throw {
        line := line.number
        message := s!"macro {Zil.MacroDef.sourceName definition} emitted an unresolved placeholder" ++
          lineStackSuffix line
        sourceLine := statement
      }
  pure instantiated

private partial def expandLine
    (definitions : Array Zil.MacroDef)
    (line : ExpandedLine)
    (fuel : Nat) : Except ParseError (Array ExpandedLine × Array Zil.MacroExpansion × Nat) := do
  match ← parseUse? line with
  | none => pure (#[line], #[], fuel)
  | some (rawName, arguments) =>
      if fuel == 0 then failAt line "macro expansion limit exceeded"
      let definition ← (definitions.find? fun candidate => Zil.MacroDef.sourceName candidate == rawName).toExcept {
        line := line.number
        message := s!"unknown macro {rawName}" ++ lineStackSuffix line
        sourceLine := line.text
      }
      if line.rawStack.contains rawName then
        throw {
          line := line.number
          message := s!"recursive macro cycle at {rawName}" ++ lineStackSuffix line
          sourceLine := line.text
        }
      let emitted ← instantiate line definition arguments
      let stack := line.stack.push definition.name
      let record : Zil.MacroExpansion := {
        macroName := definition.name
        arguments
        emitted
        stack
        rawName
        source := { frontend := "zc", line := some line.number }
      }
      let mut output : Array ExpandedLine := #[]
      let mut records : Array Zil.MacroExpansion := #[record]
      let mut remaining := fuel - 1
      for statement in emitted do
        let rawStack := line.rawStack.push rawName
        let child : ExpandedLine := { number := line.number, text := statement, stack, rawStack }
        let (childLines, childRecords, nextFuel) ← expandLine definitions child remaining
        output := output ++ childLines
        records := records ++ childRecords
        remaining := nextFuel
      pure (output, records, remaining)

private def expandPayload
    (definitions : Array Zil.MacroDef)
    (payload : Array ExpandedLine)
    (limit : Nat) : Except ParseError (Array ExpandedLine × Array Zil.MacroExpansion) := do
  let mut output : Array ExpandedLine := #[]
  let mut records : Array Zil.MacroExpansion := #[]
  let mut fuel := limit
  for line in payload do
    let (expanded, lineRecords, nextFuel) ← expandLine definitions line fuel
    output := output ++ expanded
    records := records ++ lineRecords
    fuel := nextFuel
  pure (output, records)

/-- Collect all macro definitions, remove them from the parser payload, and
recursively expand `USE` statements. The default expansion limit is 10000. Macro
control keywords are case-insensitive and inline
`//` comments outside strings are removed for lexical parity. -/
def preprocess (text : String) (limit : Nat := 10000) : Except ParseError Preprocessed := do
  let (macros, payload) ← collectDefinitions (sourceLines text) 0 #[] #[]
  let (lines, expansions) ← expandPayload macros payload limit
  pure { macros, expansions, lines }

/-- Render only the expanded source statements, primarily for CLI inspection. -/
def renderExpanded (result : Preprocessed) : String :=
  String.intercalate "\n" (result.lines.toList.map (fun line => line.text)) ++
    (if result.lines.isEmpty then "" else "\n")

end Zil.Parser.Macro
