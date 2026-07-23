import Zil

open Zil

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def macroSource : String :=
  "MACRO grant(object, group):\n" ++
  "EMIT {{object}}#viewer@{{group}}#member.\n" ++
  "ENDMACRO.\n" ++
  "\n" ++
  "MACRO grantPlatform(object):\n" ++
  "EMIT USE grant({{object}}, group:platform).\n" ++
  "ENDMACRO.\n" ++
  "\n" ++
  "group:platform#member@user:11.\n" ++
  "USE grantPlatform(doc:readme).\n" ++
  "QUERY viewers:\n" ++
  "FIND ?user WHERE doc:readme#viewer@?user.\n"

private def recursiveSource : String :=
  "MACRO loop(value):\n" ++
  "EMIT USE loop({{value}}).\n" ++
  "ENDMACRO.\n" ++
  "USE loop(doc:readme).\n"

private def aritySource : String :=
  "MACRO pair(left, right):\n" ++
  "EMIT {{left}}#related@{{right}}.\n" ++
  "ENDMACRO.\n" ++
  "USE pair(doc:readme).\n"

private def caseInsensitiveCommentSource : String :=
  "mAcRo annotate(object): // mixed-case header\n" ++
  "eMiT {{object}}#meta@value:item [note=\"https://example.test/a//b\"]. // trailing comment\n" ++
  "eNdMaCrO.\n" ++
  "uSe annotate(doc:readme). // invocation comment\n"

private def extensionSource : String :=
  "MACRO SERVICE_EXTENSION(service, team):\n" ++
  "EMIT SERVICE {{service}} [env=prod, criticality=high].\n" ++
  "EMIT {{service}}#owner@{{team}}.\n" ++
  "EMIT RULE extensionViewer:\n" ++
  "EMIT IF {{service}}#owner@?team\n" ++
  "EMIT THEN {{service}}#viewer@?team.\n" ++
  "EMIT QUERY extensionViewers:\n" ++
  "EMIT FIND ?team WHERE {{service}}#viewer@?team.\n" ++
  "ENDMACRO.\n" ++
  "USE SERVICE_EXTENSION(service:api, team:platform).\n"

private def grantLibrary : Zil.Parser.MacroProgram.LibrarySource := {
  label := "lib/10-grants.zc"
  text :=
    "mAcRo grant(object, subject):\n" ++
    "eMiT {{object}}#viewer@{{subject}}.\n" ++
    "eNdMaCrO.\n"
}

private def wrapperLibrary : Zil.Parser.MacroProgram.LibrarySource := {
  label := "lib/20-wrapper.zc"
  text :=
    "MACRO grant_platform(object):\n" ++
    "EMIT USE grant({{object}}, team:platform).\n" ++
    "ENDMACRO.\n"
}

private def libraryModel : String :=
  "MODULE macro.library.\n" ++
  "USE grant_platform(doc:readme).\n"

#guard match Zil.Parser.Macro.preprocess macroSource with
  | .ok result =>
      result.macros.size == 2 &&
      result.expansions.size == 2 &&
      result.lines.size == 4 &&
      match result.expansions[0]?, result.expansions[1]? with
      | some outer, some inner =>
          outer.source.line == some 10 &&
          inner.source.line == some 10 &&
          outer.stack.size == 1 &&
          inner.stack.size == 2
      | _, _ => false
  | .error _ => false

#guard match Zil.Parser.MacroProgram.parseText macroSource with
  | .ok program =>
      program.macros.size == 2 &&
      program.expansions.size == 2 &&
      program.tuples.size == 2 &&
      program.queries.size == 1 &&
      match program.queries[0]? with
      | some query =>
          let closed := Zil.Engine.closure program.facts program.allRules
          !(Zil.Engine.solve closed query).isEmpty
      | none => false
  | .error _ => false

#guard match Zil.Parser.Macro.preprocess caseInsensitiveCommentSource with
  | .ok result =>
      result.macros.size == 1 &&
      result.expansions.size == 1 &&
      result.lines.size == 1 &&
      match result.lines[0]? with
      | some line =>
          hasSubstring line.text "https://example.test/a//b" &&
          !hasSubstring line.text "trailing comment"
      | none => false
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText caseInsensitiveCommentSource with
  | .ok program =>
      program.tuples.size == 1 &&
      match program.tuples[0]? with
      | some tuple =>
          match tuple.attrs[0]? with
          | some attr => attr.key == `note && attr.value == .text "https://example.test/a//b"
          | none => false
      | none => false
  | .error _ => false

#guard match Zil.Parser.DeclarationProgram.parseText extensionSource with
  | .ok program =>
      program.macros.size == 1 &&
      program.expansions.size == 1 &&
      program.declarations.size == 1 &&
      program.tuples.size == 1 &&
      program.rules.size == 1 &&
      program.queries.size == 1 &&
      match program.queries[0]? with
      | some query =>
          let closed := Zil.Engine.closure program.facts program.allRules
          !(Zil.Engine.solve closed query).isEmpty
      | none => false
  | .error _ => false

#guard match Zil.Parser.MacroProgram.expandTextWithLibraries
    #[grantLibrary, wrapperLibrary] "model.zc" libraryModel with
  | .ok text =>
      hasSubstring text "doc:readme#viewer@team:platform." &&
      !hasSubstring text "USE grant_platform"
  | .error _ => false

#guard match Zil.Parser.MacroProgram.parseTextWithLibraries
    #[grantLibrary, wrapperLibrary] "model.zc" libraryModel with
  | .ok program =>
      program.macros.size == 2 &&
      program.expansions.size == 2 &&
      program.tuples.size == 1
  | .error _ => false

#guard match Zil.Parser.Macro.preprocess recursiveSource with
  | .error _ => true
  | .ok _ => false

#guard match Zil.Parser.Macro.preprocess aritySource with
  | .error _ => true
  | .ok _ => false

#guard match Zil.Parser.Macro.preprocess "USE missing(doc:readme).\n" with
  | .error _ => true
  | .ok _ => false

run_cmd do
  match Zil.Parser.MacroProgram.parseText macroSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.macros.size == 2 do
        throwError "macro definitions were not retained"
      unless program.expansions.size == 2 do
        throwError "recursive macro expansion was not recorded"
      let closed := Zil.Engine.closure program.facts program.allRules
      match program.queries[0]? with
      | none => throwError "expanded program lost its query"
      | some query =>
          unless !(Zil.Engine.solve closed query).isEmpty do
            throwError "expanded userset fact did not participate in inference"

  match Zil.Parser.DeclarationProgram.parseText extensionSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.declarations.size == 1 && program.rules.size == 1 &&
          program.queries.size == 1 do
        throwError "macro-generated extension statements were not retained"
