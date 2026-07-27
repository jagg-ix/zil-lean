import Zil.Impact
import Zil.Parser.DeclarationProgram

open Zil.Impact

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE impact.demo.\n" ++
  "lean:Parser.parse#implements@requirement:parseInput.\n" ++
  "lean:Normalize.normalize#depends_on@lean:Parser.parse.\n" ++
  "lean:Proof.sound#validates@lean:Normalize.normalize.\n" ++
  "app:cli#uses@lean:Normalize.normalize.\n" ++
  "component:ui#requires@service:api.\n" ++
  "cycle:a#depends_on@cycle:b.\n" ++
  "cycle:b#depends_on@cycle:a.\n" ++
  "RULE requirementDependency:\n" ++
  "IF ?component#requires@?service\n" ++
  "THEN ?component#depends_on@?service.\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

#guard match parsed with
  | .ok program =>
      match Zil.Engine.Provenance.traceProgram program with
      | .ok trace =>
          let graph := fromTrace trace
          graph.nodes.contains `lean.Parser.parse &&
          graph.nodes.contains `lean.Normalize.normalize &&
          graph.edges.any (fun edge =>
            edge.dependent == `component.ui &&
            edge.dependency == `service.api &&
            edge.relation == `zil.dependsOn)
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match fromProgram program with
      | .ok graph =>
          let report := analyze graph `lean.Parser.parse
          report.known && report.impacts.size == 3 &&
          match report.impacts[0]?, report.impacts[1]?, report.impacts[2]? with
          | some first, some second, some third =>
              first.node == `lean.Normalize.normalize && first.distance == 1 &&
              second.node == `app.cli && second.distance == 2 &&
              third.node == `lean.Proof.sound && third.distance == 2 &&
              first.path.size == 1 && second.path.size == 2 && third.path.size == 2
          | _, _, _ => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match fromProgram program with
      | .ok graph => graph.cyclicNodes == #[`cycle.a, `cycle.b]
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match fromProgram program with
      | .ok graph =>
          let report := analyze graph `requirement.parseInput
          report.known && report.impacts.size == 4 &&
          match report.impacts[0]? with
          | some first => first.node == `lean.Parser.parse && first.distance == 1
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match fromProgram program with
      | .ok graph =>
          let report := analyze graph `missing.node
          !report.known && report.impacts.isEmpty
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match fromProgram program, fromProgram program with
      | .ok first, .ok second =>
          first.edges == second.edges &&
          (analyze first `lean.Parser.parse).impacts.map (fun impact =>
            (impact.node, impact.distance, impact.path.map (·.factId))) ==
          (analyze second `lean.Parser.parse).impacts.map (fun impact =>
            (impact.node, impact.distance, impact.path.map (·.factId)))
      | _, _ => false
  | .error _ => false

run_cmd do
  match parsed with
  | .error error => throwError error
  | .ok program =>
      match fromProgram program with
      | .error error => throwError error
      | .ok graph =>
          let graphReport := renderGraph graph
          unless graphReport.startsWith "ZIL-DEPENDENCY-GRAPH\t1\n" do
            throwError "dependency graph report header is missing"
          unless hasSubstring graphReport "edge\tlean.Normalize.normalize\tzil.dependsOn\tlean.Parser.parse" do
            throwError "dependency graph report lost the parser dependency"
          let impactReport := renderImpact (analyze graph `lean.Parser.parse)
          unless impactReport.startsWith "ZIL-CHANGE-IMPACT\t1\n" do
            throwError "change impact report header is missing"
          unless hasSubstring impactReport "impact\tlean.Proof.sound\t2\ttransitive" do
            throwError "change impact report lost the proof impact path"
