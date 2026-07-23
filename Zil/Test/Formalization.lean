import Zil.Formalization
import Zil.Parser.DeclarationProgram

open Zil.Formalization

private def target
    (id : Name)
    (status : Status)
    (priority : Nat)
    (dependencies : Array Name := #[]) : Target := {
  id
  moduleName := "Demo"
  file := id.toString ++ ".lean"
  declaration := "Demo." ++ id.toString
  status
  priority
  dependencies
}

private def orderedTargets : Array Target := #[
  target `foundation .verified 100,
  target `lower .ready 10 #[`foundation],
  target `higher .ready 50 #[`foundation],
  target `waiting .ready 90 #[`draftDependency],
  target `draftDependency .implemented 80
]

#guard match next? orderedTargets with
  | .ok (some result) => result.id == `higher
  | _ => false

#guard match plan orderedTargets with
  | .ok decisions =>
      decisions.size == 5 &&
      decisions[0]!.target.id == `foundation &&
      decisions[1]!.target.id == `waiting &&
      !decisions[1]!.ready &&
      decisions[2]!.target.id == `draftDependency &&
      decisions[3]!.target.id == `higher &&
      decisions[3]!.ready
  | _ => false

private def tied : Array Target := #[
  target `zeta .ready 10,
  target `alpha .ready 10
]

#guard match next? tied with
  | .ok (some result) => result.id == `alpha
  | _ => false

private def cycle : Array Target := #[
  target `left .ready 1 #[`right],
  target `right .ready 1 #[`left]
]

#guard match validate cycle with
  | .error message => message.startsWith "formalization dependency cycle"
  | _ => false

private def missing : Array Target := #[
  target `child .ready 1 #[`unknown]
]

#guard match validate missing with
  | .error message => message.startsWith "missing formalization dependencies"
  | _ => false

private def duplicate : Array Target := #[
  target `same .ready 1,
  target `same .ready 2
]

#guard match validate duplicate with
  | .error message => message.startsWith "duplicate formalization targets"
  | _ => false

private def source : String :=
  "MODULE formalization.demo.\n" ++
  "FORMALIZATION_TARGET foundation " ++
    "[module=Demo, file=Foundation.lean, declaration=Demo.foundation, " ++
    "status=verified, priority=100].\n" ++
  "FORMALIZATION_TARGET next " ++
    "[module=Demo, file=Next.lean, declaration=Demo.next, " ++
    "status=ready, priority=40, dependencies=[foundation]].\n"

#guard match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program =>
      match fromProgram program with
      | .ok targets =>
          match next? targets with
          | .ok (some result) =>
              result.id == `next &&
              result.dependencies == #[`foundation]
          | _ => false
      | .error _ => false
  | .error _ => false

#guard match renderPlan orderedTargets with
  | .ok report =>
      report.startsWith "ZIL-FORMALIZATION-PLAN\t1\n" &&
      report.contains "target\thigher\tready\t50\tready"
  | .error _ => false

run_cmd do
  match Zil.Parser.DeclarationProgram.parseText source with
  | .error error => throwError error.render
  | .ok program =>
      match fromProgram program with
      | .error error => throwError error
      | .ok targets =>
          match renderNext targets with
          | .error error => throwError error
          | .ok report =>
              unless report.contains "\tnext\tDemo\tNext.lean\tDemo.next\t40\t" do
                throwError "native formalization scheduler selected the wrong target"
