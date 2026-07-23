import Zil

open Zil

private def accessSource : String :=
  "MODULE policy.active.\n" ++
  "doc:readme#viewer@user:10.\n" ++
  "doc:readme#viewer@user:11.\n" ++
  "user:11#suspended@status:true.\n" ++
  "\n" ++
  "RULE activeViewer:\n" ++
  "IF ?doc#viewer@?user AND NOT ?user#suspended@status:true\n" ++
  "THEN ?doc#active_viewer@?user.\n" ++
  "\n" ++
  "QUERY activeViewers:\n" ++
  "FIND ?user WHERE doc:readme#viewer@?user AND NOT ?user#suspended@status:true.\n"

private def unsafeNegativeSource : String :=
  "RULE unsafe:\n" ++
  "IF ?doc#viewer@?user AND NOT ?other#suspended@status:true\n" ++
  "THEN ?doc#active_viewer@?user.\n"

private def negativeCycleSource : String :=
  "seed:a#link@seed:b.\n" ++
  "RULE deriveA:\n" ++
  "IF ?x#link@?y AND NOT ?x#b@?y\n" ++
  "THEN ?x#a@?y.\n" ++
  "RULE deriveB:\n" ++
  "IF ?x#link@?y AND NOT ?x#a@?y\n" ++
  "THEN ?x#b@?y.\n"

private def activeUser10 : RelExpr :=
  .mk' (.ground `doc.readme) `zil.activeViewer (.ground `user.u10)

private def activeUser11 : RelExpr :=
  .mk' (.ground `doc.readme) `zil.activeViewer (.ground `user.u11)

#guard match Zil.Parser.Program.parseText accessSource with
  | .ok program =>
      program.valid &&
      program.rules.size == 1 &&
      match program.rules[0]? with
      | some rule =>
          rule.premises.size == 1 &&
          rule.negativePremises.size == 1 &&
          rule.safe
      | none => false
  | .error _ => false

#guard match Zil.Parser.Program.parseText accessSource with
  | .ok program =>
      match Zil.Engine.stratify program.allRules with
      | .ok strata =>
          strata.lookup `zil.viewer == 0 &&
          strata.lookup `zil.suspended == 0 &&
          strata.lookup `zil.activeViewer == 1
      | .error _ => false
  | .error _ => false

#guard match Zil.Parser.Program.parseText accessSource with
  | .ok program =>
      match Zil.Engine.closureChecked program.facts program.allRules with
      | .ok closed =>
          closed.any (fun fact => fact.semanticallyEqual activeUser10) &&
          !(closed.any fun fact => fact.semanticallyEqual activeUser11)
      | .error _ => false
  | .error _ => false

#guard match Zil.Parser.Program.parseText accessSource with
  | .ok program =>
      match program.queries[0]? with
      | some query =>
          let answers := Zil.Engine.solve program.facts query
          answers.size == 1 &&
          match answers[0]? with
          | some binding => binding.lookup `user == some (.ground `user.u10)
          | none => false
      | none => false
  | .error _ => false

#guard match Zil.Parser.Program.parseText unsafeNegativeSource with
  | .error error => error.line == 2
  | .ok _ => false

#guard match Zil.Parser.Program.parseText negativeCycleSource with
  | .error error => error.line == 1
  | .ok _ => false

private def negativeCodecRule : Rule := {
  name := `activeViewer
  variables := #[`doc, `user]
  premises := #[.mk' (.variable `doc) `zil.viewer (.variable `user)]
  negativePremises := #[.mk' (.variable `user) `zil.suspended (.ground `status.true)]
  conclusion := .mk' (.variable `doc) `zil.activeViewer (.variable `user)
}

#guard negativeCodecRule.safe
#guard Zil.Codec.ruleRoundTrips negativeCodecRule

run_cmd do
  match Zil.Parser.Program.parseText accessSource with
  | .error error => throwError error.render
  | .ok program =>
      match Zil.Engine.closureChecked program.facts program.allRules with
      | .error error => throwError error
      | .ok closed =>
          unless closed.any (fun fact => fact.semanticallyEqual activeUser10) do
            throwError "stratified closure omitted the active user"
          if closed.any (fun fact => fact.semanticallyEqual activeUser11) then
            throwError "stratified closure ignored a negative premise"
