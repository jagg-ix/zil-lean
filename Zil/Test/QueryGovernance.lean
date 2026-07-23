import Zil.QueryGovernance
import Zil.Parser.DeclarationProgram

open Zil.QueryGovernance

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE query.governance.\n" ++
  "QUERY_PACK ops_pack [queries=[q_plan, q_must], must_return=[q_must]].\n" ++
  "DSL_PROFILE ops [query_pack=ops_pack, planner_hint=high_selectivity_first].\n" ++
  "svc:api#kind@entity:service.\n" ++
  "svc:db#kind@entity:service.\n" ++
  "app:a#r_big@app:b.\n" ++
  "app:c#r_big@app:d.\n" ++
  "node:fixed#r_small@value:true.\n" ++
  "QUERY q_plan:\n" ++
  "FIND ?x WHERE ?x#r_big@?y AND node:fixed#r_small@?x.\n" ++
  "QUERY q_must:\n" ++
  "FIND ?service WHERE ?service#kind@entity:service.\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

#guard match parsed with
  | .ok program =>
      match planProgram program with
      | .ok report =>
          report.plannerHint == .highSelectivityFirst &&
          match report.queries.find? (fun query => query.name == `q_plan) with
          | some query =>
              query.original.map (·.relation) == #[`zil.rBig, `zil.rSmall] &&
              query.planned.map (·.relation) == #[`zil.rSmall, `zil.rBig]
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match checkProgram program (some `ops) with
      | .ok report =>
          report.ok &&
          report.selectedProfiles == #[`ops] &&
          report.selectedPacks == #[`ops_pack] &&
          report.selectedQueries == #[`q_plan, `q_must] &&
          match report.mustReturn[0]? with
          | some check => check.query == `q_must && check.rowCount == 2 && check.ok
          | none => false
      | .error _ => false
  | .error _ => false

private def failingSource : String :=
  "MODULE query.fail.\n" ++
  "QUERY_PACK ops_pack [queries=[q_empty], must_return=[q_empty]].\n" ++
  "DSL_PROFILE ops [query_pack=ops_pack].\n" ++
  "svc:api#kind@entity:service.\n" ++
  "QUERY q_empty:\n" ++
  "FIND ?host WHERE ?host#kind@entity:host.\n"

#guard match Zil.Parser.DeclarationProgram.parseText failingSource with
  | .ok program =>
      match checkProgram program (some `ops) with
      | .ok report =>
          !report.ok &&
          match report.mustReturn[0]? with
          | some check => !check.ok && check.rowCount == 0
          | none => false
      | .error _ => false
  | .error _ => false

private def missingPackSource : String :=
  "MODULE query.missingPack.\n" ++
  "DSL_PROFILE ops [query_pack=missing].\n" ++
  "QUERY q:\n" ++
  "FIND ?x WHERE ?x#kind@entity:item.\n"

#guard match Zil.Parser.DeclarationProgram.parseText missingPackSource with
  | .ok program =>
      match checkProgram program (some `ops) with
      | .ok report => !report.ok && report.missingPacks == #[`missing]
      | .error _ => false
  | .error _ => false

private def missingQuerySource : String :=
  "MODULE query.missingQuery.\n" ++
  "QUERY_PACK ops_pack [queries=[unknown]].\n" ++
  "DSL_PROFILE ops [query_pack=ops_pack].\n"

#guard match Zil.Parser.DeclarationProgram.parseText missingQuerySource with
  | .ok program =>
      match checkProgram program (some `ops) with
      | .ok report => !report.ok && report.missingQueries == #[`unknown]
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match checkProgram program (some `missing) with
      | .error message => message.startsWith "requested DSL profile"
      | .ok _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match planProgram program with
      | .ok report =>
          let text := renderPlan report
          text.startsWith "ZIL-QUERY-PLAN\t1\n" &&
          hasSubstring text "query\tq_plan\tx\tzil.rBig,zil.rSmall\tzil.rSmall,zil.rBig"
      | .error _ => false
  | .error _ => false

run_cmd do
  match parsed with
  | .error error => throwError error
  | .ok program =>
      match checkProgram program (some `ops) with
      | .error error => throwError error
      | .ok report =>
          unless report.ok do
            throwError "native query governance should pass the selected profile"
          unless hasSubstring (renderCi report) "must-return\tq_must\t2\tpass" do
            throwError "native query governance lost must-return evidence"
