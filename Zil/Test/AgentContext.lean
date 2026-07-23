import Zil.AgentContext
import Zil.Parser.DeclarationProgram

open Zil.AgentContext

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE agent.context.\n" ++
  "lean:Parser.parse#implements@requirement:parseInput.\n" ++
  "lean:Normalize.normalize#depends_on@lean:Parser.parse.\n" ++
  "lean:Proof.sound#validates@lean:Normalize.normalize.\n" ++
  "FORMALIZATION_TARGET parser_review [module=lean.Parser, file=Zil/Parser/Program.lean, declaration=lean.Parser.parse, status=ready, priority=90].\n" ++
  "FORMALIZATION_TARGET proof_review [module=lean.Proof, file=Zil/Proof.lean, declaration=lean.Proof.sound, status=blocked, priority=50, dependencies=[parser_review]].\n" ++
  "QUERY parserDependencies:\n" ++
  "FIND ?dependent WHERE ?dependent#depends_on@lean:Parser.parse.\n" ++
  "QUERY unrelated:\n" ++
  "FIND ?x WHERE ?x#kind@entity:service.\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

private def request : Request := {
  taskId := "task:parser-change"
  agentId := "agent:reviewer"
  scope := "Zil/Parser"
  changedNodes := #[`lean.Parser.parse]
}

#guard match parsed with
  | .ok program =>
      match build program request with
      | .ok bundle =>
          bundle.complete &&
          bundle.changedNodes == #[`lean.Parser.parse] &&
          bundle.affectedNodes == #[`lean.Normalize.normalize, `lean.Proof.sound] &&
          bundle.selectedQueries.map (·.name) == #[`parserDependencies] &&
          bundle.selectedTargets.map (·.id) == #[`parser_review, `proof_review] &&
          bundle.originatingRules.isEmpty &&
          !bundle.relevantFacts.isEmpty
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      let explicit : Request := {
        request with
        requestedQueries := #[`unrelated]
        requestedTargets := #[`proof_review]
      }
      match build program explicit with
      | .ok bundle =>
          bundle.complete &&
          bundle.selectedQueries.map (·.name) == #[`unrelated] &&
          bundle.selectedTargets.map (·.id) == #[`proof_review]
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      let incomplete : Request := {
        request with
        changedNodes := #[`missing.node]
        requestedQueries := #[`missingQuery]
        requestedTargets := #[`missingTarget]
      }
      match build program incomplete with
      | .ok bundle =>
          !bundle.complete &&
          bundle.unknownChangedNodes == #[`missing.node] &&
          bundle.missingQueries == #[`missingQuery] &&
          bundle.missingTargets == #[`missingTarget] &&
          bundle.issues.size == 3
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match build program request, build program request with
      | .ok first, .ok second => render first == render second
      | _, _ => false
  | .error _ => false

run_cmd do
  match parsed with
  | .error error => throwError error
  | .ok program =>
      match build program request with
      | .error error => throwError error
      | .ok bundle =>
          let report := render bundle
          unless report.startsWith "ZIL-AGENT-CONTEXT\t1\n" do
            throwError "agent context header is missing"
          unless hasSubstring report "impact\tlean.Parser.parse\tlean.Proof.sound\t2" do
            throwError "agent context lost transitive impact"
          unless hasSubstring report "query\tparserDependencies" do
            throwError "agent context lost the selected query"
          unless hasSubstring report "target\tparser_review" &&
                 hasSubstring report "target\tproof_review" do
            throwError "agent context lost a relevant formalization target"
