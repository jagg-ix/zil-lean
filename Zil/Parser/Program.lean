import Zil.Core.Program
import Zil.Parser.Tuple
import Zil.Engine.Query

namespace Zil.Parser.Program

private structure SourceLine where
  number : Nat
  text : String
  deriving Repr, Inhabited

private structure ParsedBody where
  positive : Array RelExpr := #[]
  negative : Array RelExpr := #[]
  deriving Repr, Inhabited

private def failAt (line : SourceLine) (message : String) : Except ParseError α :=
  .error { line := line.number, message, sourceLine := line.text }

private def sourceOf (line : SourceLine) : Source :=
  { frontend := "zc", line := some line.number }

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

private def parseAttributes (line : SourceLine) (text : String) : Except ParseError (Array Attribute) := do
  if text.trim.isEmpty then return #[]
  let mut attrs : Array Attribute := #[]
  for rawEntry in text.splitOn "," do
    let (keyText, valueText) ← match rawEntry.splitOn "=" with
      | [key, value] => pure (key.trim, value.trim)
      | _ => failAt line s!"invalid attribute entry: {rawEntry.trim}"
    if keyText.isEmpty || valueText.isEmpty then
      throw { line := line.number, message := "attribute key and value must be nonempty",
        sourceLine := line.text }
    let key ← (nameFromToken keyText).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    let value ← (parseAttrValue valueText).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    attrs := attrs.push { key, value }
  unless Attribute.keysUnique attrs do
    throw { line := line.number, message := "duplicate attribute key", sourceLine := line.text }
  pure attrs

private def splitAtomAndAttributes
    (line : SourceLine) (text : String) : Except ParseError (String × Array Attribute) := do
  match text.trim.splitOn "[" with
  | [atom] => pure (atom.trim, #[])
  | [atom, attrs] =>
      unless attrs.trim.endsWith "]" do
        throw { line := line.number, message := "attribute list must end with ']'",
          sourceLine := line.text }
      pure (atom.trim, ← parseAttributes line (attrs.trim.dropRight 1))
  | _ => failAt line "relation atom contains more than one attribute list"

private def parseRelationAtom (line : SourceLine) (text : String) : Except ParseError RelExpr := do
  let raw := text.trim
  let body := if raw.endsWith "." then raw.dropRight 1 |>.trim else raw
  let (atomText, attrs) ← splitAtomAndAttributes line body
  let (left, objectText) ← match atomText.splitOn "@" with
    | [left, object] => pure (left, object)
    | _ => failAt line "relation atom requires exactly one '@' separator"
  let (subjectText, relationText) ← match left.splitOn "#" with
    | [subject, relation] => pure (subject, relation)
    | _ => failAt line "relation atom requires one subject/relation '#' separator"
  if objectText.contains '#' then
    throw { line := line.number,
      message := "userset selectors are accepted on stored tuples, not rule/query atoms",
      sourceLine := line.text }
  let subject ← (termFromToken subjectText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  let object ← (termFromToken objectText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  let relation ← (relationNameFromToken relationText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  pure { subject, relation, object, attrs, source := sourceOf line }

/-- Parse one rule/query relation atom with source location information. -/
def parseRelationText
    (lineNumber : Nat) (sourceLine text : String) : Except ParseError RelExpr :=
  parseRelationAtom { number := lineNumber, text := sourceLine } text

private def parseBody (line : SourceLine) (text : String) : Except ParseError ParsedBody := do
  let pieces := text.trim.splitOn " AND "
  if pieces.isEmpty then
    throw { line := line.number, message := "empty relation conjunction", sourceLine := line.text }
  let mut result : ParsedBody := {}
  for piece in pieces do
    let literal := piece.trim
    if literal.isEmpty then
      throw { line := line.number, message := "empty atom in relation conjunction",
        sourceLine := line.text }
    if literal.startsWith "NOT " then
      let atomText := literal.drop 4 |>.trim
      if atomText.isEmpty then
        throw { line := line.number, message := "NOT requires a relation atom",
          sourceLine := line.text }
      result := { result with negative := result.negative.push (← parseRelationAtom line atomText) }
    else
      result := { result with positive := result.positive.push (← parseRelationAtom line literal) }
  pure result

private def parsePositiveConjunction
    (line : SourceLine) (text : String) : Except ParseError (Array RelExpr) := do
  let body ← parseBody line text
  unless body.negative.isEmpty do
    throw { line := line.number, message := "NOT is allowed in rule/query bodies only",
      sourceLine := line.text }
  pure body.positive

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def relationsVariables (relations : Array RelExpr) : Array Name :=
  relations.foldl (init := #[]) fun names relation =>
    relation.variables.foldl (init := names) pushName

private def parseHeaderName
    (line : SourceLine) (prefix : String) : Except ParseError Name := do
  let text := line.text.trim
  unless text.startsWith prefix && text.endsWith ":" do
    throw { line := line.number, message := s!"expected {prefix}<name>:", sourceLine := line.text }
  let nameText := (text.drop prefix.length).dropRight 1 |>.trim
  if nameText.isEmpty then
    throw { line := line.number, message := "declaration name is empty", sourceLine := line.text }
  (nameFromToken nameText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }

private def parseRule
    (header ifLine thenLine : SourceLine) : Except ParseError (Array Rule) := do
  let sourceName ← parseHeaderName header "RULE "
  let ifText := ifLine.text.trim
  unless ifText.startsWith "IF " do
    throw { line := ifLine.number, message := "rule body must begin with IF",
      sourceLine := ifLine.text }
  let thenText := thenLine.text.trim
  unless thenText.startsWith "THEN " && thenText.endsWith "." do
    throw { line := thenLine.number,
      message := "rule head must begin with THEN and end with '.'",
      sourceLine := thenLine.text }
  let body ← parseBody ifLine (ifText.drop 3)
  if body.positive.isEmpty then
    throw { line := ifLine.number, message := "rule requires at least one positive premise",
      sourceLine := ifLine.text }
  let heads ← parsePositiveConjunction thenLine ((thenText.drop 5).dropRight 1)
  let positiveVariables := relationsVariables body.positive
  let negativeVariables := relationsVariables body.negative
  let headVariables := relationsVariables heads
  unless negativeVariables.all positiveVariables.contains do
    throw { line := ifLine.number,
      message := "negative premise contains a variable not bound by a positive premise",
      sourceLine := ifLine.text }
  unless headVariables.all positiveVariables.contains do
    throw { line := thenLine.number,
      message := "rule head contains a variable not bound by the positive body",
      sourceLine := thenLine.text }
  let mut rules : Array Rule := #[]
  for head in heads do
    let index := rules.size
    let name := if heads.size == 1 then sourceName else Name.str sourceName s!"head_{index}"
    let rule : Rule := {
      name
      variables := positiveVariables
      premises := body.positive
      negativePremises := body.negative
      conclusion := head
      trust := .graphDerived
      source := sourceOf header }
    unless rule.safe do
      throw { line := ifLine.number, message := "unsafe rule body", sourceLine := ifLine.text }
    rules := rules.push rule
  pure rules

private def selectedVariable (line : SourceLine) (token : String) : Except ParseError Name := do
  let value := token.trim
  unless value.startsWith "?" do
    throw { line := line.number, message := s!"FIND entry must be a variable: {value}",
      sourceLine := line.text }
  (nameFromToken (value.drop 1)).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }

private def parseQuery (header findLine : SourceLine) : Except ParseError Query := do
  let name ← parseHeaderName header "QUERY "
  let text := findLine.text.trim
  unless text.startsWith "FIND " && text.endsWith "." do
    throw { line := findLine.number, message := "query must begin with FIND and end with '.'",
      sourceLine := findLine.text }
  let payload := (text.drop 5).dropRight 1 |>.trim
  let (selectText, whereText) ← match payload.splitOn " WHERE " with
    | [select, where] => pure (select, where)
    | _ => failAt findLine "query requires one WHERE clause"
  let mut select : Array Name := #[]
  for token in selectText.splitOn " " do
    if token.trim.isEmpty then continue
    select := pushName select (← selectedVariable findLine token)
  if select.isEmpty then
    throw { line := findLine.number, message := "query FIND list is empty",
      sourceLine := findLine.text }
  let body ← parseBody findLine whereText
  if body.positive.isEmpty then
    throw { line := findLine.number, message := "query requires at least one positive premise",
      sourceLine := findLine.text }
  let variables := relationsVariables body.positive
  let negativeVariables := relationsVariables body.negative
  unless negativeVariables.all variables.contains do
    throw { line := findLine.number,
      message := "negative query premise contains an unbound variable",
      sourceLine := findLine.text }
  unless select.all variables.contains do
    throw { line := findLine.number,
      message := "query selects a variable not bound by WHERE",
      sourceLine := findLine.text }
  let query : Query := {
    name, variables, select
    premises := body.positive
    negativePremises := body.negative
    source := sourceOf header }
  unless query.safe do
    throw { line := findLine.number, message := "unsafe query body", sourceLine := findLine.text }
  pure query

private def significantLines (text : String) : Array SourceLine := Id.run do
  let mut lines : Array SourceLine := #[]
  let mut number := 0
  for raw in text.splitOn "\n" do
    number := number + 1
    let trimmed := raw.trim
    if trimmed.isEmpty || trimmed.startsWith "//" then continue
    lines := lines.push { number, text := raw }
  lines

private partial def parseLines
    (lines : Array SourceLine)
    (index : Nat)
    (moduleName : Option Name)
    (tuples : Array TupleExpr)
    (rules : Array Rule)
    (queries : Array Query) : Except ParseError Zil.Program := do
  if index >= lines.size then
    if tuples.isEmpty && rules.isEmpty && queries.isEmpty then
      throw { line := 1, message := "source contains no facts, rules, or queries" }
    return { moduleName, tuples, rules, queries }
  let line := lines[index]!
  let text := line.text.trim
  if text.startsWith "MODULE " then
    if moduleName.isSome then
      throw { line := line.number, message := "duplicate MODULE declaration", sourceLine := line.text }
    unless text.endsWith "." do
      throw { line := line.number, message := "MODULE declaration must end with '.'",
        sourceLine := line.text }
    let value := (text.drop 7).dropRight 1 |>.trim
    if value.isEmpty then
      throw { line := line.number, message := "MODULE name is empty", sourceLine := line.text }
    let name ← (nameFromToken value).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    parseLines lines (index + 1) (some name) tuples rules queries
  else if text.startsWith "RULE " then
    let ifLine ← (lines.get? (index + 1)).toExcept {
      line := line.number, message := "RULE is missing its IF line", sourceLine := line.text }
    let thenLine ← (lines.get? (index + 2)).toExcept {
      line := line.number, message := "RULE is missing its THEN line", sourceLine := line.text }
    let parsed ← parseRule line ifLine thenLine
    parseLines lines (index + 3) moduleName tuples (rules ++ parsed) queries
  else if text.startsWith "QUERY " then
    let findLine ← (lines.get? (index + 1)).toExcept {
      line := line.number, message := "QUERY is missing its FIND line", sourceLine := line.text }
    let query ← parseQuery line findLine
    parseLines lines (index + 2) moduleName tuples rules (queries.push query)
  else
    let tuple ← Zil.Parser.parseTupleLine line.number line.text
    parseLines lines (index + 1) moduleName (tuples.push tuple) rules queries

/-- Parse a complete, safe, stratifiable source unit. -/
def parseText (text : String) : Except ParseError Zil.Program := do
  let program ← parseLines (significantLines text) 0 none #[] #[] #[]
  unless program.valid do
    throw { line := 1, message := "program contains an unsafe rule or query" }
  match Zil.Engine.stratify program.allRules with
  | .ok _ => pure program
  | .error message => throw { line := 1, message }

/-- Read and parse one complete `.zc` source file. -/
def parseFile (path : String) : IO (Except ParseError Zil.Program) := do
  let text ← IO.FS.readFile path
  pure (parseText text)

private def leanString (value : String) : String :=
  let escaped := value.replace "\\" "\\\\"
    |>.replace "\"" "\\\""
    |>.replace "\n" "\\n"
    |>.replace "\t" "\\t"
  "\"" ++ escaped ++ "\""

private def renderTerm : Term → String
  | .var name => s!".variable `{name}"
  | .node node => s!".ground `{node.name}"

private def renderAttrValue : AttrValue → String
  | .text value => s!".text {leanString value}"
  | .integer value => s!".integer {value}"
  | .decimal value => s!".decimal {leanString value}"
  | .boolean value => if value then ".boolean true" else ".boolean false"
  | .term term => s!".term ({renderTerm term})"

private def renderAttrs (attrs : Array Attribute) : String :=
  if attrs.isEmpty then "#[]"
  else "#[" ++ String.intercalate ", " (attrs.toList.map fun attr =>
    s!"{{ key := `{attr.key}, value := {renderAttrValue attr.value} }}") ++ "]"

private def renderSource (source : Source) : String :=
  let line := source.line.map (fun value => s!"some {value}") |>.getD "none"
  s!"{{ frontend := {leanString source.frontend}, line := {line} }}"

private def renderRelation (relation : RelExpr) : String :=
  "{ Zil.RelExpr.mkWithAttrs " ++
    s!"({renderTerm relation.subject}) `{relation.relation} " ++
    s!"({renderTerm relation.object}) {renderAttrs relation.attrs} with " ++
    s!"source := {renderSource relation.source} }}"

private def renderNames (names : Array Name) : String :=
  "#[" ++ String.intercalate ", " (names.toList.map fun name => s!"`{name}") ++ "]"

private def renderRelations (relations : Array RelExpr) : String :=
  "#[" ++ String.intercalate ",\n      " (relations.toList.map renderRelation) ++ "]"

private def renderRule (index : Nat) (rule : Rule) : String :=
  s!"private def sourceRule{index} : Zil.Rule := {{\n" ++
    s!"  name := `{rule.name}\n" ++
    s!"  variables := {renderNames rule.variables}\n" ++
    s!"  premises := {renderRelations rule.premises}\n" ++
    s!"  negativePremises := {renderRelations rule.negativePremises}\n" ++
    s!"  conclusion := {renderRelation rule.conclusion}\n" ++
    "  trust := .graphDerived\n" ++
    s!"  source := {renderSource rule.source}\n}}"

private def renderQuery (index : Nat) (query : Query) : String :=
  s!"def sourceQuery{index} : Zil.Query := {{\n" ++
    s!"  name := `{query.name}\n" ++
    s!"  variables := {renderNames query.variables}\n" ++
    s!"  select := {renderNames query.select}\n" ++
    s!"  premises := {renderRelations query.premises}\n" ++
    s!"  negativePremises := {renderRelations query.negativePremises}\n" ++
    s!"  source := {renderSource query.source}\n}}"

/-- Render the complete source program as native Lean declarations. -/
def renderLeanModule (program : Zil.Program) (namespaceName : Name) : Except String String := do
  let base ← Zil.Parser.renderLeanModule program.tupleProgram namespaceName
  let mut ruleDefs : Array String := #[]
  let mut ruleNames : Array String := #[]
  let mut registrations : Array String := #[]
  for rule in program.rules do
    let index := ruleDefs.size
    ruleDefs := ruleDefs.push (renderRule index rule)
    ruleNames := ruleNames.push s!"sourceRule{index}"
    registrations := registrations.push s!"zil_register_rule sourceRule{index}"
  let mut queryDefs : Array String := #[]
  let mut queryNames : Array String := #[]
  for query in program.queries do
    let index := queryDefs.size
    queryDefs := queryDefs.push (renderQuery index query)
    queryNames := queryNames.push s!"sourceQuery{index}"
  let moduleName := match program.moduleName with
    | none => "none"
    | some name => s!"some `{name}"
  let renderedRuleNames := String.intercalate ", " ruleNames.toList
  let renderedQueryNames := String.intercalate ", " queryNames.toList
  let extension :=
    s!"\nnamespace {namespaceName}\n\n" ++
    String.intercalate "\n\n" ruleDefs.toList ++
    (if ruleDefs.isEmpty || queryDefs.isEmpty then "" else "\n\n") ++
    String.intercalate "\n\n" queryDefs.toList ++
    (if ruleDefs.isEmpty && queryDefs.isEmpty then "" else "\n\n") ++
    String.intercalate "\n" registrations.toList ++
    (if registrations.isEmpty then "" else "\n\n") ++
    "def sourceProgram : Zil.Program := {\n" ++
    s!"  moduleName := {moduleName}\n" ++
    "  tuples := sourceTuples\n" ++
    s!"  rules := #[{renderedRuleNames}]\n" ++
    s!"  queries := #[{renderedQueryNames}]\n" ++
    "}\n\n" ++
    s!"end {namespaceName}\n"
  pure (base ++ extension)

/-- Namespace derived from the source module or the tuple parser fallback. -/
def defaultNamespace (program : Zil.Program) : Name :=
  Zil.Parser.defaultNamespace program.tupleProgram

end Zil.Parser.Program
