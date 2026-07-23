import Zil.Core.Program
import Zil.Parser.Tuple

namespace Zil.Parser.Program

private structure SourceLine where
  number : Nat
  text : String
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
      return ← failAt line "attribute key and value must be nonempty"
    let key ← (nameFromToken keyText).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    let value ← (parseAttrValue valueText).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    attrs := attrs.push { key, value }
  unless Attribute.keysUnique attrs do
    return ← failAt line "duplicate attribute key"
  pure attrs

private def splitAtomAndAttributes
    (line : SourceLine) (text : String) : Except ParseError (String × Array Attribute) := do
  match text.trim.splitOn "[" with
  | [atom] => pure (atom.trim, #[])
  | [atom, attrs] =>
      unless attrs.trim.endsWith "]" do
        return ← failAt line "attribute list must end with ']'"
      pure (atom.trim, ← parseAttributes line (attrs.trim.dropRight 1))
  | _ => failAt line "relation atom contains more than one attribute list"

/-- Parse one direct relation atom used in a rule or query. -/
def parseRelationAtom (line : SourceLine) (text : String) : Except ParseError RelExpr := do
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
    return ← failAt line "userset selectors are accepted on stored tuples, not rule/query atoms"
  let subject ← (termFromToken subjectText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  let object ← (termFromToken objectText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  let relation ← (relationNameFromToken relationText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }
  pure { subject, relation, object, attrs, source := sourceOf line }

private def parseConjunction (line : SourceLine) (text : String) : Except ParseError (Array RelExpr) := do
  let pieces := text.trim.splitOn " AND "
  if pieces.isEmpty then return ← failAt line "empty relation conjunction"
  let mut relations : Array RelExpr := #[]
  for piece in pieces do
    relations := relations.push (← parseRelationAtom line piece)
  pure relations

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def valueVariables (value : AttrValue) : Array Name :=
  match value with
  | .term (.var name) => #[name]
  | _ => #[]

private def relationVariables (relation : RelExpr) : Array Name :=
  let names := match relation.subject with
    | .var name => #[name]
    | .node _ => #[]
  let names := match relation.object with
    | .var name => pushName names name
    | .node _ => names
  relation.attrs.foldl (init := names) fun names attr =>
    (valueVariables attr.value).foldl (init := names) pushName

private def relationsVariables (relations : Array RelExpr) : Array Name :=
  relations.foldl (init := #[]) fun names relation =>
    (relationVariables relation).foldl (init := names) pushName

private def parseHeaderName
    (line : SourceLine) (prefix : String) : Except ParseError Name := do
  let text := line.text.trim
  unless text.startsWith prefix && text.endsWith ":" do
    return ← failAt line s!"expected {prefix}<name>:"
  let nameText := (text.drop prefix.length).dropRight 1 |>.trim
  if nameText.isEmpty then return ← failAt line "declaration name is empty"
  (nameFromToken nameText).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }

private def parseRule
    (header ifLine thenLine : SourceLine) : Except ParseError (Array Rule) := do
  let sourceName ← parseHeaderName header "RULE "
  let ifText := ifLine.text.trim
  unless ifText.startsWith "IF " do
    return ← failAt ifLine "rule body must begin with IF"
  let thenText := thenLine.text.trim
  unless thenText.startsWith "THEN " && thenText.endsWith "." do
    return ← failAt thenLine "rule head must begin with THEN and end with '.'"
  let premises ← parseConjunction ifLine (ifText.drop 3)
  let heads ← parseConjunction thenLine ((thenText.drop 5).dropRight 1)
  let bodyVariables := relationsVariables premises
  let headVariables := relationsVariables heads
  unless headVariables.all bodyVariables.contains do
    return ← failAt thenLine "rule head contains a variable not bound by the IF body"
  let mut rules : Array Rule := #[]
  for head in heads do
    let index := rules.size
    let name := if heads.size == 1 then sourceName else Name.str sourceName s!"head_{index}"
    rules := rules.push {
      name
      variables := bodyVariables
      premises
      conclusion := head
      trust := .graphDerived
      source := sourceOf header }
  pure rules

private def selectedVariable (line : SourceLine) (token : String) : Except ParseError Name := do
  let value := token.trim
  unless value.startsWith "?" do
    return ← failAt line s!"FIND entry must be a variable: {value}"
  (nameFromToken (value.drop 1)).mapError fun message =>
    { line := line.number, message, sourceLine := line.text }

private def parseQuery (header findLine : SourceLine) : Except ParseError Query := do
  let name ← parseHeaderName header "QUERY "
  let text := findLine.text.trim
  unless text.startsWith "FIND " && text.endsWith "." do
    return ← failAt findLine "query must begin with FIND and end with '.'"
  let payload := (text.drop 5).dropRight 1 |>.trim
  let (selectText, whereText) ← match payload.splitOn " WHERE " with
    | [select, where] => pure (select, where)
    | _ => failAt findLine "query requires one WHERE clause"
  let mut select : Array Name := #[]
  for token in selectText.splitOn " " do
    if token.trim.isEmpty then continue
    select := pushName select (← selectedVariable findLine token)
  if select.isEmpty then return ← failAt findLine "query FIND list is empty"
  let premises ← parseConjunction findLine whereText
  let variables := relationsVariables premises
  unless select.all variables.contains do
    return ← failAt findLine "query selects a variable not bound by WHERE"
  pure { name, variables, select, premises, source := sourceOf header }

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
    if moduleName.isSome then return ← failAt line "duplicate MODULE declaration"
    unless text.endsWith "." do return ← failAt line "MODULE declaration must end with '.'"
    let value := (text.drop 7).dropRight 1 |>.trim
    let name ← (nameFromToken value).mapError fun message =>
      { line := line.number, message, sourceLine := line.text }
    parseLines lines (index + 1) (some name) tuples rules queries
  else if text.startsWith "RULE " then
    let ifLine ← lines[index + 1]?.toExcept {
      line := line.number, message := "RULE is missing its IF line", sourceLine := line.text }
    let thenLine ← lines[index + 2]?.toExcept {
      line := line.number, message := "RULE is missing its THEN line", sourceLine := line.text }
    let parsed ← parseRule line ifLine thenLine
    parseLines lines (index + 3) moduleName tuples (rules ++ parsed) queries
  else if text.startsWith "QUERY " then
    let findLine ← lines[index + 1]?.toExcept {
      line := line.number, message := "QUERY is missing its FIND line", sourceLine := line.text }
    let query ← parseQuery line findLine
    parseLines lines (index + 2) moduleName tuples rules (queries.push query)
  else
    let tuple ← Zil.Parser.parseTupleLine line.number line.text
    parseLines lines (index + 1) moduleName (tuples.push tuple) rules queries

/-- Parse a complete source unit containing tuples, rules, and queries. -/
def parseText (text : String) : Except ParseError Zil.Program :=
  parseLines (significantLines text) 0 none #[] #[] #[]

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

private def renderRule (index : Nat) (rule : Rule) : String :=
  let premises := "#[" ++ String.intercalate ",\n      "
    (rule.premises.toList.map renderRelation) ++ "]"
  s!"private def sourceRule{index} : Zil.Rule := {{\n" ++
    s!"  name := `{rule.name}\n" ++
    s!"  variables := {renderNames rule.variables}\n" ++
    s!"  premises := {premises}\n" ++
    s!"  conclusion := {renderRelation rule.conclusion}\n" ++
    "  trust := .graphDerived\n" ++
    s!"  source := {renderSource rule.source}\n}}"

private def renderQuery (index : Nat) (query : Query) : String :=
  let premises := "#[" ++ String.intercalate ",\n      "
    (query.premises.toList.map renderRelation) ++ "]"
  s!"def sourceQuery{index} : Zil.Query := {{\n" ++
    s!"  name := `{query.name}\n" ++
    s!"  variables := {renderNames query.variables}\n" ++
    s!"  select := {renderNames query.select}\n" ++
    s!"  premises := {premises}\n" ++
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
    s!"  rules := #[{String.intercalate ", " ruleNames.toList}]\n" ++
    s!"  queries := #[{String.intercalate ", " queryNames.toList}]\n" ++
    "}\n\n" ++
    s!"end {namespaceName}\n"
  pure (base ++ extension)

/-- Namespace derived from the source module or the tuple parser fallback. -/
def defaultNamespace (program : Zil.Program) : Name :=
  Zil.Parser.defaultNamespace program.tupleProgram

end Zil.Parser.Program
