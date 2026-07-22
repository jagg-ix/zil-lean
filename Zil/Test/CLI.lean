import Zil.CLI.Core

open Zil

private def fact : RelExpr :=
  .mk' (.ground `lean.CLI.theorem) `zil.formalizes (.ground `claim.cli)

private def session : Zil.CLI.Session :=
  ⟨{ knowledgeRevision := 3, facts := #[fact] }⟩

#guard Zil.CLI.execute session .summary |>.contains "revision: 3"
#guard Zil.CLI.execute session (.check fact) == "true"
#guard Zil.CLI.execute session .closure |>.contains "claim.cli"

run_cmd do
  match Zil.CLI.parseCommand "export prolog" with
  | .ok (.export .prolog) => pure ()
  | _ => throwError "CLI did not parse export command"
  match Zil.CLI.parseCommand "unknown" with
  | .error _ => pure ()
  | _ => throwError "CLI accepted an unknown command"
