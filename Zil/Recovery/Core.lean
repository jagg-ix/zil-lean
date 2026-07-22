import Lean
import Zil.Contract.Core

namespace Zil.Recovery

open Lean

/-- A rollback point recorded before a mutating formalization action. -/
structure Checkpoint where
  name : Name
  knowledgeRevision : Nat
  contractName : Option Name := none
  contractRevision : Option Nat := none
  deriving Repr, Inhabited

abbrev CheckpointState := Array Checkpoint

private def appendCheckpoint (state : CheckpointState) (checkpoint : Checkpoint) : CheckpointState :=
  if state.any fun current => current.name == checkpoint.name then state else state.push checkpoint

private def importCheckpoints (states : Array CheckpointState) : CheckpointState :=
  states.foldl (init := #[]) fun acc state => state.foldl (init := acc) appendCheckpoint

initialize checkpointExtension : SimplePersistentEnvExtension Checkpoint CheckpointState ←
  registerSimplePersistentEnvExtension {
    name := `zilRecoveryCheckpointExtension
    addEntryFn := appendCheckpoint
    addImportedFn := importCheckpoints
  }

def checkpoints (env : Environment) : CheckpointState := checkpointExtension.getState env

def containsCheckpoint (env : Environment) (name : Name) : Bool :=
  (checkpoints env).any fun checkpoint => checkpoint.name == name

def addCheckpoint (checkpoint : Checkpoint) : CoreM Unit :=
  modifyEnv fun env => checkpointExtension.addEntry env checkpoint

/-- Context acquired by an agent before proposing a mutation. -/
structure ContextToken where
  knowledgeRevision : Nat
  contractName : Option Name := none
  contractRevision : Option Nat := none
  checkpoint : Option Name := none
  theoremIntentMismatchResolved : Bool := true
  deriving Repr, Inhabited

inductive RejectionKind where
  | staleKnowledgeRevision
  | contractChanged
  | unresolvedTheoremIntentMismatch
  | missingRollbackCheckpoint
  deriving Repr, BEq, Inhabited

structure Rejection where
  kind : RejectionKind
  message : String
  deriving Repr, Inhabited

/-- Capture the current optimistic-concurrency context for one contract. -/
def capture (env : Environment) (contractName : Option Name := none)
    (checkpoint : Option Name := none) : ContextToken :=
  let contractRevision := contractName.bind fun name =>
    (Zil.Contract.latest? env name).map (·.revision)
  { knowledgeRevision := Zil.Engine.knowledgeRevision env
    contractName
    contractRevision
    checkpoint }

/-- Reject a mutation whose context is stale or unsafe. -/
def validateMutation (env : Environment) (token : ContextToken) : Array Rejection :=
  let issues := #[]
  let issues :=
    if token.knowledgeRevision == Zil.Engine.knowledgeRevision env then issues
    else issues.push { kind := .staleKnowledgeRevision
      message := "knowledge revision changed after context acquisition" }
  let currentContractRevision := token.contractName.bind fun name =>
    (Zil.Contract.latest? env name).map (·.revision)
  let issues :=
    if currentContractRevision == token.contractRevision then issues
    else issues.push { kind := .contractChanged
      message := "formalization contract changed after context acquisition" }
  let issues :=
    if token.theoremIntentMismatchResolved then issues
    else issues.push { kind := .unresolvedTheoremIntentMismatch
      message := "critical theorem-intent mismatch remains unresolved" }
  match token.checkpoint with
  | some name =>
      if containsCheckpoint env name then issues
      else issues.push { kind := .missingRollbackCheckpoint
        message := s!"rollback checkpoint {name} is not registered" }
  | none => issues.push { kind := .missingRollbackCheckpoint
      message := "mutating action has no rollback checkpoint" }

def mutationAllowed (env : Environment) (token : ContextToken) : Bool :=
  (validateMutation env token).isEmpty

end Zil.Recovery
