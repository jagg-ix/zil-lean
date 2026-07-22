import Lean
import Zil.Recovery.Core

namespace Zil.Syntax

open Lean Elab Command

syntax (name := zilCheckpointDecl) "zil_checkpoint " ident : command

macro_rules
  | `(zil_checkpoint $name:ident) =>
      `(run_cmd do
          let env ← getEnv
          Zil.Recovery.addCheckpoint {
            name := $(quote name.getId)
            knowledgeRevision := Zil.Engine.knowledgeRevision env })

syntax (name := zilCheckMutationDecl) "#zil_check_mutation " term : command

elab_rules : command
  | `(#zil_check_mutation $token:term) => do
      let tokenValue ← liftTermElabM do
        let expression ← Elab.Term.elabTermEnsuringType token (mkConst ``Zil.Recovery.ContextToken)
        Meta.evalExpr Zil.Recovery.ContextToken (mkConst ``Zil.Recovery.ContextToken) expression
      let issues := Zil.Recovery.validateMutation (← getEnv) tokenValue
      unless issues.isEmpty do
        throwError m!"mutation rejected:\n{MessageData.joinSep (issues.map fun issue => m!"[{repr issue.kind}] {issue.message}") (m!"\n")}"

end Zil.Syntax
