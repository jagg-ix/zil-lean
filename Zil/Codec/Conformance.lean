import Zil.Parser.DeclarationProgram
import Zil.Codec.Attribute
import Zil.Engine.Query

namespace Zil.Codec.Conformance

private def escape (value : String) : String :=
  value.replace "\\" "\\\\"
    |>.replace "\t" "\\t"
    |>.replace "\n" "\\n"
    |>.replace "\r" "\\r"

private def encodeTerm : Zil.Term → String
  | .var name => "var:" ++ name.toString
  | .node node => "node:" ++ node.name.toString

private def insertString (value : String) : List String → List String
  | [] => [value]
  | head :: tail =>
      match compare value head with
      | .lt | .eq => value :: head :: tail
      | .gt => head :: insertString value tail

private def sortedStrings (values : Array String) : List String :=
  values.foldl (init := []) fun out value => insertString value out

private def encodeAttributes (attrs : Array Zil.Attribute) : String :=
  let values := attrs.map fun attr =>
    attr.key.toString ++ "=" ++ Zil.Codec.encodeAttrValue attr.value
  String.intercalate ";" (sortedStrings values)

/-- Source-insensitive relation encoding with map-order-independent attributes. -/
def encodeRelation (relation : Zil.RelExpr) : String :=
  String.intercalate "\t" [
    "rel",
    encodeTerm relation.subject,
    relation.relation.toString,
    encodeTerm relation.object,
    encodeAttributes relation.attrs
  ]

private def encodeTuple (tuple : Zil.TupleExpr) : String :=
  let prefix := [
    "tuple",
    encodeTerm tuple.object,
    tuple.relation.toString
  ]
  let suffix := match tuple.subject with
    | .direct subject => ["direct", encodeTerm subject]
    | .userset userset =>
        ["userset", userset.object.name.toString, userset.relation.toString]
  String.intercalate "\t" (prefix ++ suffix ++ [encodeAttributes tuple.attrs])

private def trustName : Zil.TrustClass → String
  | .asserted => "asserted"
  | .graphDerived => "graphDerived"
  | .certified => "certified"

private def encodeRelations (relations : Array Zil.RelExpr) : String :=
  let encoded := relations.map (escape ∘ encodeRelation)
  String.intercalate "|" (sortedStrings encoded)

private def encodeRule (rule : Zil.Rule) : String :=
  String.intercalate "\t" [
    "rule",
    String.intercalate "," (rule.variables.toList.map Name.toString),
    trustName rule.trust,
    encodeRelations rule.premises,
    encodeRelations rule.negativePremises,
    escape (encodeRelation rule.conclusion)
  ]

private def encodeNames (names : Array Name) : String :=
  String.intercalate "," (names.toList.map Name.toString)

private def encodeQuery (query : Zil.Query) : String :=
  String.intercalate "\t" [
    "query",
    query.name.toString,
    encodeNames query.variables,
    encodeNames query.select,
    encodeRelations query.premises,
    encodeRelations query.negativePremises
  ]

private def encodeBinding (query : Zil.Query) (binding : Zil.Engine.Binding) : String :=
  String.intercalate ";" <| query.select.toList.map fun name =>
    let value := match binding.lookup name with
      | some term => encodeTerm term
      | none => "unbound"
    name.toString ++ "=" ++ value

private def macroLines (program : Zil.Program) : Array String := Id.run do
  let mut out := #[]
  for definition in program.macros do
    out := out.push <| String.intercalate "\t" [
      "macro", definition.name.toString, encodeNames definition.parameters]
    let mut index := 0
    for statement in definition.emit do
      out := out.push <| String.intercalate "\t" [
        "macro-emit", definition.name.toString, toString index, escape statement]
      index := index + 1
  for expansion in program.expansions do
    out := out.push <| String.intercalate "\t" [
      "expansion",
      expansion.macroName.toString,
      String.intercalate "," (expansion.arguments.toList.map escape),
      String.intercalate "," (expansion.stack.toList.map Name.toString)]
    let mut index := 0
    for statement in expansion.emitted do
      out := out.push <| String.intercalate "\t" [
        "expansion-emit", expansion.macroName.toString, toString index, escape statement]
      index := index + 1
  return out

private def semanticLines (program : Zil.Program) : Array String := Id.run do
  let mut out := macroLines program
  for tuple in program.tuples do
    out := out.push ("tuple\t" ++ escape (encodeTuple tuple))
  for declaration in program.declarations do
    out := out.push <| String.intercalate "\t" [
      "declaration", declaration.kind.keyword, declaration.entityName.toString]
  for fact in program.facts do
    out := out.push ("fact\t" ++ escape (encodeRelation fact))
  for rule in program.allRules do
    out := out.push (encodeRule rule)
  let closed := Zil.Engine.closure program.facts program.allRules
  for fact in closed do
    out := out.push ("closed\t" ++ escape (encodeRelation fact))
  for query in program.queries do
    out := out.push (encodeQuery query)
    for binding in Zil.Engine.solve closed query do
      out := out.push <| String.intercalate "\t" [
        "query-row", query.name.toString, escape (encodeBinding query binding)]
  return out

/-- Deterministic semantic report used by the cross-runtime differential harness. -/
def render (program : Zil.Program) : String :=
  let moduleName := program.moduleName.map Name.toString |>.getD "-"
  let header := ["ZILC\t1", "module\t" ++ moduleName]
  String.intercalate "\n" (header ++ sortedStrings (semanticLines program)) ++ "\n"

/-- Parse a complete source unit and render its semantic report. -/
def renderSource (source : String) : Except String String := do
  let program ← (Zil.Parser.DeclarationProgram.parseText source).mapError (·.render)
  pure (render program)

end Zil.Codec.Conformance
