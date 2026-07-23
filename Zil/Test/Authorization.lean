import Zil.Authorization
import Zil.Parser.DeclarationProgram

open Zil.Authorization

private def source : String :=
  "MODULE authorization.demo.\n" ++
  "group:eng#member@user:11.\n" ++
  "doc:readme#viewer@group:eng#member.\n" ++
  "doc:readme#owner@user:10.\n" ++
  "service:api#depends_on@service:db.\n" ++
  "RULE serviceAccess:\n" ++
  "IF ?service#depends_on@?dependency AND ?dependency#operator@?user\n" ++
  "THEN ?service#operator@?user.\n" ++
  "service:db#operator@user:12.\n"

private def request (object relation subject : Name) : Request := {
  object := .ground object
  relation
  subject := .ground subject
}

private def parsedProgram : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

#guard match parsedProgram with
  | .ok program =>
      match decide program (request `doc.readme `zil.viewer `user.u11) with
      | .ok decision =>
          decision.allowed && decision.source == .derived &&
          !decision.derivingRules.isEmpty
      | .error _ => false
  | .error _ => false

#guard match parsedProgram with
  | .ok program =>
      match decide program (request `doc.readme `zil.owner `user.u10) with
      | .ok decision => decision.allowed && decision.source == .direct
      | .error _ => false
  | .error _ => false

#guard match parsedProgram with
  | .ok program =>
      match decide program (request `service.api `zil.operator `user.u12) with
      | .ok decision => decision.allowed && decision.source == .derived
      | .error _ => false
  | .error _ => false

#guard match parsedProgram with
  | .ok program =>
      match decide program (request `doc.readme `zil.viewer `user.u99) with
      | .ok decision => !decision.allowed && decision.source == .none
      | .error _ => false
  | .error _ => false

#guard match parsedProgram with
  | .ok program =>
      let invalid : Request := {
        object := .variable `document
        relation := `zil.viewer
        subject := .ground `user.u11
      }
      match decide program invalid with
      | .error message => message == "authorization request must be ground"
      | .ok _ => false
  | .error _ => false

#guard match parsedProgram with
  | .ok program =>
      match decide program (request `doc.readme `zil.viewer `user.u11) with
      | .ok decision =>
          let report := render decision
          report.startsWith "ZIL-AUTHORIZATION\t1\n" &&
          (report.splitOn "decision\tallow").length > 1 &&
          (report.splitOn "source\tderived").length > 1
      | .error _ => false
  | .error _ => false

run_cmd do
  match parsedProgram with
  | .error error => throwError error
  | .ok program =>
      match decide program (request `doc.readme `zil.viewer `user.u11) with
      | .error error => throwError error
      | .ok decision =>
          unless decision.allowed do
            throwError "userset authorization should allow user.u11"
          unless decision.source == .derived do
            throwError "userset authorization should be rule-derived"
