import Zil

open Zil

private def extensionLibrary : Zil.Parser.MacroProgram.LibrarySource := {
  label := "lib/20-service-extension.zc"
  text :=
    "mAcRo SERVICE_EXTENSION(service, team):\n" ++
    "eMiT SERVICE {{service}} [env=prod, criticality=high].\n" ++
    "eMiT {{service}}#owner@{{team}}.\n" ++
    "eMiT RULE extensionViewer:\n" ++
    "eMiT IF {{service}}#owner@?team\n" ++
    "eMiT THEN {{service}}#viewer@?team.\n" ++
    "eMiT QUERY extensionViewers:\n" ++
    "eMiT FIND ?team WHERE {{service}}#viewer@?team.\n" ++
    "eNdMaCrO.\n"
}

private def modelSource : String :=
  "MODULE macro.library.extension.\n" ++
  "uSe SERVICE_EXTENSION(service:api, team:platform). // model invocation\n"

#guard match Zil.Parser.DeclarationProgram.parseTextWithLibraries
    #[extensionLibrary] "model.zc" modelSource with
  | .ok program =>
      program.macros.size == 1 &&
      program.expansions.size == 1 &&
      program.declarations.size == 1 &&
      program.tuples.size == 1 &&
      program.rules.size == 1 &&
      program.queries.size == 1 &&
      match program.declarations[0]?, program.queries[0]? with
      | some declaration, some query =>
          declaration.kind == .service &&
          declaration.name == `service.api &&
          let closed := Zil.Engine.closure program.facts program.allRules
          !(Zil.Engine.solve closed query).isEmpty
      | _, _ => false
  | .error _ => false

#guard match Zil.Parser.MacroProgram.expandTextWithLibraries
    #[extensionLibrary] "model.zc" modelSource with
  | .ok expanded =>
      (expanded.splitOn "SERVICE service:api").length > 1 &&
      (expanded.splitOn "RULE extensionViewer:").length > 1 &&
      (expanded.splitOn "QUERY extensionViewers:").length > 1 &&
      (expanded.splitOn "USE SERVICE_EXTENSION").length == 1
  | .error _ => false

run_cmd do
  match Zil.Parser.DeclarationProgram.parseTextWithLibraries
      #[extensionLibrary] "model.zc" modelSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.declarations.size == 1 do
        throwError "library macro did not emit its typed declaration"
      unless program.rules.size == 1 && program.queries.size == 1 do
        throwError "library macro did not emit its rule and query extensions"
