import Zil.Parser.MacroProgram
import Zil.Parser.Declaration
import Zil.Syntax.Declaration

namespace Zil.Parser.DeclarationProgram

private def parseModuleOnly
    (lines : Array Zil.Parser.Macro.ExpandedLine) : Except ParseError Zil.Program := do
  let modules := lines.filter fun line => line.text.trim.startsWith "MODULE "
  let others := lines.filter fun line => !line.text.trim.startsWith "MODULE "
  unless others.isEmpty do
    throw { line := others[0]!.number, message := "source payload could not be parsed", sourceLine := others[0]!.text }
  if modules.isEmpty then
    pure {}
  else if modules.size == 1 then
    let line := modules[0]!
    let text := line.text.trim
    unless text.endsWith "." do
      throw { line := line.number, message := "MODULE declaration must end with '.'", sourceLine := line.text }
    let nameText := (text.drop 7).dropRight 1 |>.trim
    let name ← (Zil.Parser.nameFromToken nameText).mapError fun message => {
      line := line.number, message, sourceLine := line.text }
    pure { moduleName := some name }
  else
    throw { line := modules[1]!.number, message := "duplicate MODULE declaration", sourceLine := modules[1]!.text }

/-- Expand macros, collect typed declarations, and parse the remaining tuples,
rules, and queries. -/
def parseText (text : String) (limit : Nat := 10000) : Except ParseError Zil.Program := do
  let preprocessed ← Zil.Parser.Macro.preprocess text limit
  let (declarations, payload) ← Zil.Parser.Declaration.collect preprocessed.lines
  let semantic ←
    if payload.all (fun line => line.text.trim.startsWith "MODULE ") then
      parseModuleOnly payload
    else
      Zil.Parser.Program.parseText (Zil.Parser.Declaration.renderPayload payload)
  let program : Zil.Program := {
    semantic with
    macros := preprocessed.macros
    expansions := preprocessed.expansions
    declarations
  }
  unless program.valid do
    throw { line := 1, message := "program contains an invalid declaration, rule, or query" }
  pure program

/-- Read one complete macro- and declaration-enabled source file. -/
def parseFile (path : String) (limit : Nat := 10000) : IO (Except ParseError Zil.Program) := do
  let text ← IO.FS.readFile path
  pure (parseText text limit)

private def leanString (value : String) : String :=
  let escaped := value.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"
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

private partial def renderValue : DeclValue → String
  | .scalar value => s!".scalar ({renderAttrValue value})"
  | .list values =>
      ".list #[" ++ String.intercalate ", " (values.toList.map renderValue) ++ "]"
  | .set values =>
      ".set #[" ++ String.intercalate ", " (values.toList.map renderValue) ++ "]"
  | .map entries =>
      ".map #[" ++ String.intercalate ", " (entries.toList.map fun entry =>
        s!"({renderValue entry.1}, {renderValue entry.2})") ++ "]"

private def renderSource (source : Source) : String :=
  let line := source.line.map (fun value => s!"some {value}") |>.getD "none"
  s!"{{ frontend := {leanString source.frontend}, line := {line} }}"

private def renderKind : DeclarationKind → String
  | .service => "service"
  | .host => "host"
  | .datasource => "datasource"
  | .metric => "metric"
  | .policy => "policy"
  | .event => "event"
  | .provider => "provider"
  | .tmAtom => "tmAtom"
  | .ltsAtom => "ltsAtom"
  | .refines => "refines"
  | .corresponds => "corresponds"
  | .proofObligation => "proofObligation"
  | .formalizationTarget => "formalizationTarget"
  | .languageProfile => "languageProfile"
  | .grammarProfile => "grammarProfile"
  | .parserAdapter => "parserAdapter"
  | .dslProfile => "dslProfile"
  | .queryPack => "queryPack"

private def renderDeclaration (index : Nat) (declaration : Declaration) : String :=
  let attrs := "#[" ++ String.intercalate ", " (declaration.attrs.toList.map fun attr =>
    s!"{{ key := `{attr.key}, value := {renderValue attr.value} }}") ++ "]"
  s!"private def sourceDeclaration{index} : Zil.Declaration := {{\n" ++
    s!"  kind := .{renderKind declaration.kind}\n" ++
    s!"  name := `{declaration.name}\n" ++
    s!"  attrs := {attrs}\n" ++
    s!"  source := {renderSource declaration.source}\n}}"

/-- Render declarations beside the ordinary generated tuple/rule/query module. -/
def renderLeanModule (program : Zil.Program) (namespaceName : Name) : Except String String := do
  let base ← Zil.Parser.Program.renderLeanModule program namespaceName
  let mut definitions : Array String := #[]
  let mut names : Array String := #[]
  let mut registrations : Array String := #[]
  for declaration in program.declarations do
    let index := definitions.size
    definitions := definitions.push (renderDeclaration index declaration)
    names := names.push s!"sourceDeclaration{index}"
    registrations := registrations.push s!"zil_register_declaration sourceDeclaration{index}"
  let extension :=
    if definitions.isEmpty then ""
    else
      s!"\nnamespace {namespaceName}\n\n" ++
      String.intercalate "\n\n" definitions.toList ++ "\n\n" ++
      "def sourceDeclarations : Array Zil.Declaration := #[" ++
      String.intercalate ", " names.toList ++ "]\n\n" ++
      "#zil_check_declarations sourceDeclarations\n\n" ++
      String.intercalate "\n" registrations.toList ++ "\n\n" ++
      "def completeSourceProgram : Zil.Program := {\n" ++
      "  sourceProgram with\n" ++
      "  declarations := sourceDeclarations\n" ++
      "}\n\n" ++
      s!"end {namespaceName}\n"
  pure (base ++ extension)

/-- Namespace derived from the source module. -/
def defaultNamespace (program : Zil.Program) : Name :=
  Zil.Parser.Program.defaultNamespace program

end Zil.Parser.DeclarationProgram
