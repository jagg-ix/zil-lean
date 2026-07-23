import Zil

open Zil

private def containsText (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def attrSource : String :=
  "MODULE service.map.\n" ++
  "service:api#depends_on@service:db [critical=true, retries=3, ratio=0.75, owner=team:platform, note=\"primary\"].\n"

private def expectedAttrs : Array Attribute := #[
  { key := `critical, value := .boolean true },
  { key := `retries, value := .integer 3 },
  { key := `ratio, value := .decimal "0.75" },
  { key := `owner, value := .term (.ground `team.platform) },
  { key := `note, value := .text "primary" }
]

private def attributedRelation : RelExpr :=
  .mkWithAttrs (.ground `service.api) `zil.dependsOn (.ground `service.db) expectedAttrs

private def sameAttrsDifferentOrder : Array Attribute := #[
  { key := `note, value := .text "primary" },
  { key := `owner, value := .term (.ground `team.platform) },
  { key := `ratio, value := .decimal "0.75" },
  { key := `retries, value := .integer 3 },
  { key := `critical, value := .boolean true }
]

#guard Attribute.keysUnique expectedAttrs
#guard Attribute.arraysSemanticallyEqual expectedAttrs sameAttrsDifferentOrder
#guard Zil.Codec.relationRoundTrips attributedRelation

#guard match Zil.Parser.parseText attrSource with
  | .ok program =>
      program.moduleName == some `service.map &&
      program.tuples.size == 1 &&
      match program.tuples[0]? with
      | some tuple =>
          tuple.attrs.size == 5 &&
          tuple.lowerFact.semanticallyEqual attributedRelation
      | none => false
  | .error _ => false

#guard match Zil.Parser.parseText
    "service:api#depends_on@service:db [critical=true, critical=false].\n" with
  | .error _ => true
  | .ok _ => false

private def attrQuery : Query := {
  name := `criticalDependency
  variables := #[]
  select := #[]
  premises := #[
    RelExpr.mkWithAttrs
      (.ground `service.api)
      `zil.dependsOn
      (.ground `service.db)
      #[{ key := `critical, value := .boolean true }]
  ]
}

#guard !(Zil.Engine.solve #[attributedRelation] attrQuery).isEmpty

private def wrongAttrQuery : Query := {
  attrQuery with
  name := `noncriticalDependency
  premises := #[
    RelExpr.mkWithAttrs
      (.ground `service.api)
      `zil.dependsOn
      (.ground `service.db)
      #[{ key := `critical, value := .boolean false }]
  ]
}

#guard (Zil.Engine.solve #[attributedRelation] wrongAttrQuery).isEmpty

run_cmd do
  match Zil.Parser.parseText attrSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.tuples.size == 1 do
        throwError "attribute parser returned the wrong tuple count"
      match Zil.Parser.renderLeanModule program (Zil.Parser.defaultNamespace program) with
      | .error error => throwError error
      | .ok rendered =>
          unless containsText rendered "zil_register_tuple sourceTuple0" do
            throwError "generated module did not register its lossless tuple"
