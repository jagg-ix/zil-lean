import Zil.Parser.Tuple

open Zil

private def accessSource : String :=
  "MODULE policy.access.\n" ++
  "doc:readme#owner@user:10.\n" ++
  "group:eng#member@user:11.\n" ++
  "doc:readme#viewer@group:eng#member.\n" ++
  "doc:readme#parent@folder:A.\n"

private def directSource : String :=
  "doc:readme#viewer@group:eng.\n"

private def usersetSource : String :=
  "doc:readme#viewer@group:eng#member.\n"

#guard match Zil.Parser.nameFromToken "user:10" with
  | .ok name => name == `user.u10
  | .error _ => false

#guard match Zil.Parser.relationNameFromToken "supported_by" with
  | .ok name => name == `zil.supportedBy
  | .error _ => false

#guard match Zil.Parser.parseText accessSource with
  | .ok program =>
      program.moduleName == some `policy.access &&
      program.tuples.size == 4 &&
      program.lower.facts.size == 4 &&
      program.lower.rules.size == 1 &&
      match program.tuples[2]? with
      | some tuple =>
          tuple.source.line == some 4 &&
          match tuple.subject with
          | .userset userset =>
              userset.object.name == `group.eng && userset.relation == `zil.member
          | .direct _ => false
      | none => false
  | .error _ => false

#guard match Zil.Parser.parseText directSource, Zil.Parser.parseText usersetSource with
  | .ok directProgram, .ok usersetProgram =>
      match directProgram.tuples[0]?, usersetProgram.tuples[0]? with
      | some directTuple, some usersetTuple =>
          !directTuple.semanticallyEqual usersetTuple
      | _, _ => false
  | _, _ => false

#guard match Zil.Parser.parseText accessSource with
  | .ok program =>
      match Zil.Parser.renderLeanModule program (Zil.Parser.defaultNamespace program) with
      | .ok rendered => !rendered.isEmpty
      | .error _ => false
  | .error _ => false

#guard match Zil.Parser.parseText "doc:readme#owner@user:10\n" with
  | .error error => error.line == 1
  | .ok _ => false

run_cmd do
  match Zil.Parser.parseText accessSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.tuples.size == 4 do
        throwError "native tuple parser returned the wrong tuple count"
      match Zil.Parser.renderLeanModule program (Zil.Parser.defaultNamespace program) with
      | .error error => throwError error
      | .ok _ => pure ()
