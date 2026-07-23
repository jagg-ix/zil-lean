import Zil

open Zil

private def programSource : String :=
  "MODULE policy.access.\n" ++
  "doc:readme#viewer@group:eng [source=manual].\n" ++
  "group:eng#member@user:11.\n" ++
  "\n" ++
  "RULE groupViewer:\n" ++
  "IF ?document#viewer@?group [source=manual] AND ?group#member@?user\n" ++
  "THEN ?document#viewer@?user [source=manual] AND ?document#auditable@?user.\n" ++
  "\n" ++
  "QUERY viewers:\n" ++
  "FIND ?user WHERE doc:readme#viewer@?user [source=manual].\n"

private def unsafeRuleSource : String :=
  "RULE unsafe:\n" ++
  "IF ?document#viewer@?group\n" ++
  "THEN ?document#viewer@?user.\n"

private def unsafeQuerySource : String :=
  "QUERY unsafe:\n" ++
  "FIND ?missing WHERE doc:readme#viewer@?user.\n"

#guard match Zil.Parser.Program.parseText programSource with
  | .ok program =>
      program.moduleName == some `policy.access &&
      program.tuples.size == 2 &&
      program.rules.size == 2 &&
      program.queries.size == 1 &&
      program.valid &&
      match program.rules[0]?, program.rules[1]? with
      | some first, some second =>
          first.name == `groupViewer.head_0 &&
          second.name == `groupViewer.head_1 &&
          first.variables == #[`document, `group, `user]
      | _, _ => false
  | .error _ => false

#guard match Zil.Parser.Program.parseText unsafeRuleSource with
  | .error error => error.line == 3
  | .ok _ => false

#guard match Zil.Parser.Program.parseText unsafeQuerySource with
  | .error error => error.line == 2
  | .ok _ => false

#guard match Zil.Parser.Program.parseText programSource with
  | .ok program =>
      let closed := Zil.Engine.closure program.facts program.allRules
      let expected := RelExpr.mkWithAttrs
        (.ground `doc.readme)
        `zil.viewer
        (.ground `user.u11)
        #[{ key := `source, value := .term (.ground `manual) }]
      closed.any (fun fact => fact.semanticallyEqual expected)
  | .error _ => false

#guard match Zil.Parser.Program.parseText programSource with
  | .ok program =>
      match program.queries[0]? with
      | some query =>
          let closed := Zil.Engine.closure program.facts program.allRules
          !(Zil.Engine.solve closed query).isEmpty
      | none => false
  | .error _ => false

run_cmd do
  match Zil.Parser.Program.parseText programSource with
  | .error error => throwError error.render
  | .ok program =>
      unless program.rules.size == 2 do
        throwError "multi-head source rule was not normalized"
      unless program.queries.size == 1 do
        throwError "source query was not retained"
      match Zil.Parser.Program.renderLeanModule
          program (Zil.Parser.Program.defaultNamespace program) with
      | .error error => throwError error
      | .ok rendered =>
          unless rendered.contains "sourceRule0" do
            throwError "generated Lean omitted source rules"
          unless rendered.contains "sourceQuery0" do
            throwError "generated Lean omitted source queries"
          unless rendered.contains "sourceProgram" do
            throwError "generated Lean omitted the source program value"
