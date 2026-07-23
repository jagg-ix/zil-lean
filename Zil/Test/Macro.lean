import Zil

open Zil

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
