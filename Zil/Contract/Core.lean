import Lean
import Zil.Engine.Report

namespace Zil.Contract

open Lean

inductive CompletionStatus where
  | proposed
  | inProgress
  | complete
  deriving Repr, BEq, Inhabited

/-- A persistent, revisioned statement of what one formalization module promises. -/
structure FileContract where
  name : Name
  revision : Nat
  advertisedScope : String
  abstractionLevel : String
  requiredDeclarations : Array Name := #[]
  requiredRelations : Array Zil.RelExpr := #[]
  forbiddenDeclarations : Array Name := #[]
  status : CompletionStatus := .proposed
  deriving Repr, Inhabited

inductive IssueKind where
  | missingDeclaration
  | missingRelation
  | forbiddenSubstitution
  | weakenedScope
  | prematureCompletion
  deriving Repr, BEq, Inhabited

structure Issue where
  contract : Name
  revision : Nat
  kind : IssueKind
  message : String
  deriving Repr, Inhabited

abbrev ContractState := Array FileContract

private def sameRequiredDeclaration (left right : FileContract) : Bool :=
  left.requiredDeclarations.all right.requiredDeclarations.contains

private def sameRequiredRelation (left right : FileContract) : Bool :=
  left.requiredRelations.all fun relation =>
    right.requiredRelations.any (·.semanticallyEqual relation)

private def appendContract (state : ContractState) (contract : FileContract) : ContractState :=
  if state.any fun current => current.name == contract.name && current.revision == contract.revision
  then state
  else state.push contract

private def importContracts (states : Array ContractState) : ContractState :=
  states.foldl (init := #[]) fun acc state => state.foldl (init := acc) appendContract

initialize contractExtension : SimplePersistentEnvExtension FileContract ContractState ←
  registerSimplePersistentEnvExtension {
    name := `zilContractExtension
    addEntryFn := appendContract
    addImportedFn := importContracts
  }

/-- Register a contract in the current module and export it through `.olean`. -/
def add (contract : FileContract) : CoreM Unit :=
  modifyEnv fun env => contractExtension.addEntry env contract

def contracts (env : Environment) : ContractState := contractExtension.getState env

def latest? (env : Environment) (name : Name) : Option FileContract :=
  (contracts env).foldl (init := none) fun best current =>
    if current.name != name then best else
    match best with
    | none => some current
    | some previous => if previous.revision < current.revision then some current else best

private def previous? (env : Environment) (contract : FileContract) : Option FileContract :=
  (contracts env).foldl (init := none) fun best current =>
    if current.name != contract.name || current.revision >= contract.revision then best else
    match best with
    | none => some current
    | some previous => if previous.revision < current.revision then some current else best

private def push (issues : Array Issue) (contract : FileContract)
    (kind : IssueKind) (message : String) : Array Issue :=
  issues.push { contract := contract.name, revision := contract.revision, kind, message }

/-- Validate one contract against Lean declarations and closed graph knowledge. -/
def validate (env : Environment) (contract : FileContract) (fuel : Nat := 64) : Array Issue :=
  let closed := Zil.Engine.closureOfEnvironment env fuel
  let issues := contract.requiredDeclarations.foldl (init := #[]) fun issues declaration =>
    if env.contains declaration then issues
    else push issues contract .missingDeclaration s!"missing required declaration {declaration}"
  let issues := contract.requiredRelations.foldl (init := issues) fun issues relation =>
    if closed.any (·.semanticallyEqual relation) then issues
    else push issues contract .missingRelation s!"missing required relation {repr relation}"
  let issues := contract.forbiddenDeclarations.foldl (init := issues) fun issues declaration =>
    if env.contains declaration then
      push issues contract .forbiddenSubstitution s!"forbidden substitute declaration is present: {declaration}"
    else issues
  let issues := match previous? env contract with
    | none => issues
    | some previous =>
        if sameRequiredDeclaration previous contract && sameRequiredRelation previous contract then issues
        else push issues contract .weakenedScope "contract revision removed previously required objects"
  if contract.status == .complete && !issues.isEmpty then
    push issues contract .prematureCompletion "contract is marked complete while blocking issues remain"
  else issues

def validateLatest (env : Environment) (fuel : Nat := 64) : Array Issue :=
  let names := (contracts env).foldl (init := #[]) fun names contract =>
    if names.contains contract.name then names else names.push contract.name
  names.foldl (init := #[]) fun issues name =>
    match latest? env name with
    | none => issues
    | some contract => issues ++ validate env contract fuel

end Zil.Contract
