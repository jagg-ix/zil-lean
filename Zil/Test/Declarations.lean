import Zil

open Zil

private def declarationSource : String :=
  "MODULE stdlib.native.\n" ++
  "SERVICE db [env=prod].\n" ++
  "SERVICE api [env=prod, uses=service:db].\n" ++
  "DATASOURCE app_metrics [type=rest, format=json].\n" ++
  "METRIC latency [source=datasource:app_metrics, unit=ms].\n" ++
  "QUERY dependencies:\n" ++
  "FIND ?dependency WHERE service:api#dependsOn@?dependency.\n"

private def tmSource : String :=
  "MODULE tm.native.\n" ++
  "TM_ATOM parity [states=#{q0 qa qr}, alphabet=#{0 _}, blank=_, initial=q0, " ++
  "accept=#{qa}, reject=#{qr}, transitions={[q0 0] [q0 0 :R], [q0 _] [qa _ :N]}].\n"

private def macroDeclarationSource : String :=
  "MACRO service(name):\n" ++
  "EMIT SERVICE {{name}} [env=prod].\n" ++
  "ENDMACRO.\n" ++
  "MODULE generated.services.\n" ++
  "USE service(api).\n"

private def cycleSource : String :=
  "SERVICE a [uses=service:b].\n" ++
  "SERVICE b [uses=service:a].\n"

private def missingReferenceSource : String :=
  "SERVICE api [uses=service:missing].\n"

private def invalidEnumSource : String :=
  "SERVICE api [env=outer_space].\n"

#guard match Zil.Parser.DeclarationProgram.parseText declarationSource with
  | .ok program =>
      program.declarations.size == 4 &&
      program.queries.size == 1 &&
      program.valid &&
      let facts := program.facts
      facts.any (fun fact => fact.semanticallyEqual
        (.mk' (.ground `service.api) `zil.uses (.ground `service.db))) &&
      facts.any (fun fact => fact.semanticallyEqual
        (.mk' (.ground `service.db) `zil.usedBy (.ground `service.api))) &&
      facts.any (fun fact => fact.semanticallyEqual
        (.mk' (.ground `service.api) `zil.dependsOn (.ground `service.db)))
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText declarationSource with
  | .ok program =>
      match program.queries[0]? with
      | some query => !(Zil.Engine.solve program.facts query).isEmpty
      | none => false
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText tmSource with
  | .ok program =>
      program.declarations.size == 1 &&
      (program.facts.filter fun fact => fact.relation == `zil.transition).size == 2
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText macroDeclarationSource with
  | .ok program =>
      program.macros.size == 1 &&
      program.expansions.size == 1 &&
      program.declarations.size == 1 &&
      program.declarations[0]!.entityName == `service.api
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText cycleSource with
  | .error _ => true
  | .ok _ => false

#guard match Zil.Parser.DeclarationProgram.parseText missingReferenceSource with
  | .error _ => true
  | .ok _ => false

#guard match Zil.Parser.DeclarationProgram.parseText invalidEnumSource with
  | .error _ => true
  | .ok _ => false

private def containsText (value needle : String) : Bool :=
  (value.splitOn needle).length > 1

run_cmd do
  match Zil.Parser.DeclarationProgram.parseText declarationSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.declarations.size == 4 do
        throwError "typed declarations were not retained"
      match Zil.Parser.DeclarationProgram.renderLeanModule
          program (Zil.Parser.DeclarationProgram.defaultNamespace program) with
      | .error error => throwError error
      | .ok rendered =>
          unless containsText rendered "sourceDeclaration0" do
            throwError "generated Lean omitted declaration definitions"
          unless containsText rendered "zil_register_declaration" do
            throwError "generated Lean omitted declaration registration"
          unless containsText rendered "completeSourceProgram" do
            throwError "generated Lean omitted the complete source program"
