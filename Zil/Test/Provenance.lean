import Zil.Engine.Provenance
import Zil.Parser.DeclarationProgram

open Zil.Engine.Provenance

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE provenance.demo.\n" ++
  "group:eng#member@user:11.\n" ++
  "doc:readme#viewer@group:eng#member.\n" ++
  "service:db#kind@entity:service.\n" ++
  "doc:readme#parent@folder:a.\n" ++
  "folder:a#parent@folder:b.\n" ++
  "RULE degraded:\n" ++
  "IF service:db#kind@entity:service AND NOT service:db#available@value:true\n" ++
  "THEN service:db#status@value:degraded.\n" ++
  "RULE ancestorBase:\n" ++
  "IF ?child#parent@?parent\n" ++
  "THEN ?child#ancestor@?parent.\n" ++
  "RULE ancestorStep:\n" ++
  "IF ?child#ancestor@?middle AND ?middle#parent@?ancestor\n" ++
  "THEN ?child#ancestor@?ancestor.\n" ++
  "QUERY viewers:\n" ++
  "FIND ?user WHERE doc:readme#viewer@?user.\n" ++
  "QUERY ancestors:\n" ++
  "FIND ?ancestor WHERE doc:readme#ancestor@?ancestor.\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

private def viewerFact : Zil.RelExpr :=
  .mk' (.ground `doc.readme) `zil.viewer (.ground `user.u11)

private def degradedFact : Zil.RelExpr :=
  .mk' (.ground `service.db) `zil.status (.ground `value.degraded)

private def transitiveFact : Zil.RelExpr :=
  .mk' (.ground `doc.readme) `zil.ancestor (.ground `folder.b)

#guard match parsed with
  | .ok program =>
      match traceProgram program with
      | .ok trace =>
          match trace.findFact? viewerFact with
          | some node =>
              match node.origin with
              | .rule _ premises negatives _ => premises.size == 2 && negatives.isEmpty
              | .base => false
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match traceProgram program with
      | .ok trace =>
          match trace.findFact? degradedFact with
          | some node =>
              match node.origin with
              | .rule rule premises negatives _ =>
                  rule == `degraded && premises.size == 1 && negatives.size == 1 &&
                  negatives[0]!.relation == `zil.available
              | .base => false
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match traceProgram program with
      | .ok trace =>
          match trace.findFact? transitiveFact with
          | some node =>
              match node.origin with
              | .rule rule premises _ _ => rule == `ancestorStep && premises.size == 2
              | .base => false
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match traceProgram program with
      | .ok trace =>
          match program.queries.find? (fun query => query.name == `viewers) with
          | some query =>
              match queryWitnesses trace query with
              | #[witness] =>
                  witness.premiseFactIds.size == 1 &&
                  match witness.selected[0]? with
                  | some selected => selected.1 == `user && selected.2 == .ground `user.u11
                  | none => false
              | _ => false
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match traceProgram program with
      | .ok trace =>
          let missing : Zil.RelExpr :=
            .mk' (.ground `doc.readme) `zil.viewer (.ground `user.u99)
          let explanation := explainFact trace missing
          !explanation.allowed && explanation.factId.isNone && explanation.source == "none"
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match traceProgram program, traceProgram program with
      | .ok first, .ok second =>
          first.facts.map (fun node => (node.id, Zil.Codec.encodeRelation node.fact)) ==
          second.facts.map (fun node => (node.id, Zil.Codec.encodeRelation node.fact))
      | _, _ => false
  | .error _ => false

run_cmd do
  match parsed with
  | .error error => throwError error
  | .ok program =>
      match traceProgram program with
      | .error error => throwError error
      | .ok trace =>
          let report := renderTrace trace
          unless report.startsWith "ZIL-PROVENANCE\t1\n" do
            throwError "provenance report header is missing"
          unless hasSubstring report "origin" do
            throwError "provenance report lost origin rows"
          match program.queries.find? (fun query => query.name == `ancestors) with
          | none => throwError "ancestor query is missing"
          | some query =>
              let witnesses := queryWitnesses trace query
              unless witnesses.size == 2 do
                throwError "ancestor query should retain direct and transitive witnesses"
              unless hasSubstring (renderQueryWitnesses trace query witnesses) "premise" do
                throwError "query explanation lost premise evidence"
