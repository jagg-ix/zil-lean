module

public meta import Zil.Datalog.Claim
public meta import Lean.Elab.Command

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

/-- How far a declaration or file promises to go. The order is deliberately
explicit: it is used only for accountability checks, never as a mathematical
coercion between levels. -/
meta inductive AbstractionLevel where
  | syntactic
  | algebraic
  | structural
  | toyModel
  | domainModel
  | physicalTheorem
  | bridgeTheorem
  | interpretation
  deriving Repr, BEq, Inhabited

meta def AbstractionLevel.rank : AbstractionLevel → Nat
  | .syntactic => 0
  | .algebraic => 1
  | .structural => 2
  | .toyModel => 3
  | .domainModel => 4
  | .physicalTheorem => 5
  | .bridgeTheorem => 6
  | .interpretation => 7

meta def AbstractionLevel.label : AbstractionLevel → String
  | .syntactic => "syntactic"
  | .algebraic => "algebraic"
  | .structural => "structural"
  | .toyModel => "toy_model"
  | .domainModel => "domain_model"
  | .physicalTheorem => "physical_theorem"
  | .bridgeTheorem => "bridge_theorem"
  | .interpretation => "interpretation"

meta def AbstractionLevel.ofName? : Name → Option AbstractionLevel
  | `syntactic => some .syntactic
  | `algebraic => some .algebraic
  | `structural => some .structural
  | `toy_model => some .toyModel
  | `domain_model => some .domainModel
  | `physical_theorem => some .physicalTheorem
  | `bridge_theorem => some .bridgeTheorem
  | `interpretation => some .interpretation
  | _ => none

meta inductive ContractStatus where
  | scaffold
  | incomplete
  | satisfied
  | reviewed
  deriving Repr, BEq, Inhabited

meta def ContractStatus.label : ContractStatus → String
  | .scaffold => "scaffold"
  | .incomplete => "incomplete"
  | .satisfied => "satisfied"
  | .reviewed => "reviewed"

meta def ContractStatus.ofName? : Name → Option ContractStatus
  | `scaffold => some .scaffold
  | `incomplete => some .incomplete
  | `satisfied => some .satisfied
  | `reviewed => some .reviewed
  | _ => none

/-- A requirement is deliberately textual so contracts may name work that does
not exist yet. Requirements beginning with `lean:` are executable: the linter
checks that the named declaration exists in the current environment. -/
meta structure FileContract where
  name : Name
  module : Name
  sourceFile : String
  promise : String
  level : AbstractionLevel
  status : ContractStatus
  requirements : Array String
  forbiddenSubstitutes : Array String
  witnesses : Array Name
  deriving Repr, Inhabited

meta structure ContractState where
  entries : List FileContract := []
  deriving Repr, Inhabited

meta def ContractState.add (state : ContractState) (entry : FileContract) : ContractState :=
  { entries := state.entries.filter (·.name != entry.name) ++ [entry] }

meta initialize fileContractExt :
    SimplePersistentEnvExtension FileContract ContractState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.fileContractExt
    addEntryFn := ContractState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl ContractState.add state) {}
  }

meta def fileContract? (env : Environment) (name : Name) : Option FileContract :=
  (fileContractExt.getState env).entries.find? (·.name == name)

meta def fileContracts (env : Environment) : Array FileContract :=
  (fileContractExt.getState env).entries.toArray

meta structure TheoremIntent where
  declaration : Name
  module : Name
  sourceFile : String
  level : AbstractionLevel
  requiredMentions : Array Name
  deriving Repr, Inhabited

meta structure TheoremIntentState where
  entries : List TheoremIntent := []
  deriving Repr, Inhabited

meta def TheoremIntentState.add (state : TheoremIntentState)
    (entry : TheoremIntent) : TheoremIntentState :=
  { entries := state.entries.filter (·.declaration != entry.declaration) ++ [entry] }

meta initialize theoremIntentExt :
    SimplePersistentEnvExtension TheoremIntent TheoremIntentState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.theoremIntentExt
    addEntryFn := TheoremIntentState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl TheoremIntentState.add state) {}
  }

meta def theoremIntent? (env : Environment) (declaration : Name) : Option TheoremIntent :=
  (theoremIntentExt.getState env).entries.find? (·.declaration == declaration)

meta def theoremIntents (env : Environment) : Array TheoremIntent :=
  (theoremIntentExt.getState env).entries.toArray

private meta def parseLevel (stx : Syntax) : CommandElabM AbstractionLevel := do
  let name := stx.getId
  let some level := AbstractionLevel.ofName? name
    | throwErrorAt stx
        "unknown ZIL abstraction level '{name}'; expected syntactic, algebraic, structural, \
        toy_model, domain_model, physical_theorem, bridge_theorem, or interpretation"
  pure level

private meta def parseStatus (stx : Syntax) : CommandElabM ContractStatus := do
  let name := stx.getId
  let some status := ContractStatus.ofName? name
    | throwErrorAt stx
        "unknown ZIL contract status '{name}'; expected scaffold, incomplete, satisfied, or reviewed"
  pure status

private meta def resolveMany (items : Array (TSyntax `ident)) : CommandElabM (Array Name) :=
  items.mapM resolveGlobalConstNoOverload

syntax (name := zilFileContractCmd)
  "zil_file_contract" ident "where"
    "promises" str
    "at_level" ident
    "contract_status" ident
    "requires_objects" "[" str,* "]"
    "forbids_substitutes" "[" str,* "]"
    "witnessed_by" "[" ident,* "]" : command

@[command_elab zilFileContractCmd]
meta def elabZilFileContract : CommandElab := fun stx => do
  match stx with
  | `(command| zil_file_contract $name:ident where
      promises $promiseTextSyntax:str
      at_level $levelName:ident
      contract_status $statusName:ident
      requires_objects [$requirements:str,*]
      forbids_substitutes [$forbidden:str,*]
      witnessed_by [$witnessItems:ident,*]) =>
      let env ← getEnv
      let contractName := name.getId
      if (fileContract? env contractName).isSome then
        throwErrorAt name "duplicate ZIL file contract '{contractName}'"
      let promiseText := promiseTextSyntax.getString
      if promiseText.trimAscii.isEmpty then
        throwErrorAt promiseTextSyntax "a ZIL file contract must state a nonempty promise"
      let requirements := requirements.getElems.map (·.getString)
      unless requirements.toList.eraseDups.length = requirements.size do
        throwErrorAt stx "ZIL file-contract requirements must be unique"
      let forbidden := forbidden.getElems.map (·.getString)
      unless forbidden.toList.eraseDups.length = forbidden.size do
        throwErrorAt stx "ZIL forbidden-substitute descriptions must be unique"
      let witnesses ← resolveMany witnessItems.getElems
      unless witnesses.toList.eraseDups.length = witnesses.size do
        throwErrorAt stx "ZIL file-contract witnesses must be unique"
      let sourceFile ← getFileName
      let contractLevel ← parseLevel levelName
      let contractStatus ← parseStatus statusName
      modifyEnv fun current => fileContractExt.addEntry current {
        name := contractName
        module := env.mainModule
        sourceFile
        promise := promiseText
        level := contractLevel
        status := contractStatus
        requirements
        forbiddenSubstitutes := forbidden
        witnesses
      }
  | _ => throwUnsupportedSyntax

syntax (name := zilTheoremIntentCmd)
  "zil_theorem_intent" ident "where"
    "at_level" ident
    "must_mention" "[" ident,* "]" : command

@[command_elab zilTheoremIntentCmd]
meta def elabZilTheoremIntent : CommandElab := fun stx => do
  match stx with
  | `(command| zil_theorem_intent $target:ident where
      at_level $levelName:ident
      must_mention [$mentionItems:ident,*]) =>
      let declaration ← resolveGlobalConstNoOverload target
      let env ← getEnv
      if (theoremIntent? env declaration).isSome then
        throwErrorAt target "duplicate ZIL theorem intent for '{declaration}'"
      let some info := env.find? declaration
        | throwErrorAt target "unknown Lean declaration '{declaration}'"
      unless ← liftTermElabM <| Meta.isProp info.type do
        throwErrorAt target
          "ZIL theorem intents may be attached only to declarations whose type is a proposition"
      let intentLevel ← parseLevel levelName
      match zilLevelAttr.getParam? env declaration with
        | none => pure ()
        | some attributeLevelName =>
            let some parsed := AbstractionLevel.ofName? attributeLevelName
              | throwErrorAt target
                  "theorem '{declaration}' has unknown @[zil_level {attributeLevelName}]"
            unless parsed == intentLevel do
              throwErrorAt levelName
                "theorem-intent level '{intentLevel.label}' disagrees with \
                @[zil_level {parsed.label}]"
      let requiredMentions ← resolveMany mentionItems.getElems
      unless requiredMentions.toList.eraseDups.length = requiredMentions.size do
        throwErrorAt stx "ZIL theorem-intent mentions must be unique"
      let sourceFile ← getFileName
      modifyEnv fun current => theoremIntentExt.addEntry current {
        declaration
        module := env.mainModule
        sourceFile
        level := intentLevel
        requiredMentions
      }
  | _ => throwUnsupportedSyntax

private meta def missingLeanRequirements (env : Environment)
    (contract : FileContract) : Array String :=
  contract.requirements.filter fun requirement =>
    if requirement.startsWith "lean:" then
      let declaration := (requirement.drop 5).toName
      (env.find? declaration).isNone
    else
      false

private meta def executableRequirements (contract : FileContract) : Array String :=
  contract.requirements.filter (·.startsWith "lean:")

private meta def unverifiableRequirements (contract : FileContract) : Array String :=
  contract.requirements.filter (!·.startsWith "lean:")

private meta def declarationLevel? (env : Environment)
    (declaration : Name) : Option AbstractionLevel :=
  match zilLevelAttr.getParam? env declaration with
  | some levelName => AbstractionLevel.ofName? levelName
  | none => (theoremIntent? env declaration).map (·.level)

private meta def invalidWitnessLevels (env : Environment)
    (contract : FileContract) : Array Name :=
  contract.witnesses.filter fun witness =>
    (declarationLevel? env witness).isNone

private meta def strongestWitnessLevel? (env : Environment)
    (contract : FileContract) : Option AbstractionLevel :=
  contract.witnesses.foldl (init := none) fun strongest witness =>
    match declarationLevel? env witness with
    | none => strongest
    | some witnessLevel =>
        match strongest with
        | none => some witnessLevel
        | some current =>
            if current.rank < witnessLevel.rank then some witnessLevel else some current

private meta def missingIntentMentions (env : Environment)
    (intent : TheoremIntent) : Array Name :=
  let used := (env.find? intent.declaration).map (·.type.getUsedConstantsAsSet) |>.getD {}
  intent.requiredMentions.filter fun required => !used.contains required

private meta def contractProblems (env : Environment)
    (contract : FileContract) : Array String := Id.run do
  let mut problems := #[]
  let missing := missingLeanRequirements env contract
  if !missing.isEmpty then
    problems := problems.push s!"missing executable requirements: {missing.toList}"
  let unverifiable := unverifiableRequirements contract
  if !unverifiable.isEmpty then
    problems := problems.push
      s!"requirements without an executable checker (use contract status incomplete): {unverifiable.toList}"
  let invalidLevels := invalidWitnessLevels env contract
  if !invalidLevels.isEmpty then
    problems := problems.push s!"unclassified witnesses: {invalidLevels.toList}"
  match strongestWitnessLevel? env contract with
  | none =>
      problems := problems.push "the contract has no classified theorem witness"
  | some strongest =>
      if strongest.rank < contract.level.rank then
        problems := problems.push
          s!"promised level {contract.level.label} exceeds strongest witness level {strongest.label}"
  for witness in contract.witnesses do
    if let some intent := theoremIntent? env witness then
      let missingMentions := missingIntentMentions env intent
      if !missingMentions.isEmpty then
        problems := problems.push
          s!"theorem intent for {witness} is missing statement-level mentions: {missingMentions.toList}"
  return problems

private meta def requireContract (stx : Syntax) (name : Name) : CommandElabM FileContract := do
  let some contract := fileContract? (← getEnv) name
    | throwErrorAt stx "unknown ZIL file contract '{name}'"
  pure contract

syntax (name := zilShowFileContractCmd) "#zil_file_contract " ident : command
syntax (name := zilMissingRequirementsCmd) "#zil_missing_requirements " ident : command
syntax (name := zilFormalizationLintCmd) "#zil_formalization_lint " ident : command
syntax (name := zilFormalizationLintAllCmd) "#zil_formalization_lint_all" : command
syntax (name := zilShowTheoremIntentCmd) "#zil_theorem_intent " ident : command

@[command_elab zilShowFileContractCmd]
meta def elabShowFileContract : CommandElab := fun stx => do
  let `(#zil_file_contract $name:ident) := stx | throwUnsupportedSyntax
  let contract ← requireContract name name.getId
  logInfo m!"ZIL file contract '{contract.name}': promise={contract.promise}, \
    level={contract.level.label}, status={contract.status.label}, \
    requirements={contract.requirements.toList}, forbids={contract.forbiddenSubstitutes.toList}, \
    witnesses={contract.witnesses.toList}"

@[command_elab zilMissingRequirementsCmd]
meta def elabMissingRequirements : CommandElab := fun stx => do
  let `(#zil_missing_requirements $name:ident) := stx | throwUnsupportedSyntax
  let contract ← requireContract name name.getId
  let missing := missingLeanRequirements (← getEnv) contract
  logInfo m!"ZIL missing requirements for '{contract.name}': {missing.toList}"

@[command_elab zilShowTheoremIntentCmd]
meta def elabShowTheoremIntent : CommandElab := fun stx => do
  let `(#zil_theorem_intent $target:ident) := stx | throwUnsupportedSyntax
  let declaration ← resolveGlobalConstNoOverload target
  let some intent := theoremIntent? (← getEnv) declaration
    | throwErrorAt target "no ZIL theorem intent is registered for '{declaration}'"
  let missing := missingIntentMentions (← getEnv) intent
  logInfo m!"ZIL theorem intent '{declaration}': level={intent.level.label}, \
    mentions={intent.requiredMentions.toList}, missing={missing.toList}"

@[command_elab zilFormalizationLintCmd]
meta def elabFormalizationLint : CommandElab := fun stx => do
  let `(#zil_formalization_lint $name:ident) := stx | throwUnsupportedSyntax
  let contract ← requireContract name name.getId
  let env ← getEnv
  let problems := contractProblems env contract
  let executable := executableRequirements contract
  let coverage :=
    if executable.isEmpty then 100
    else
      let missing := (missingLeanRequirements env contract).size
      ((executable.size - missing) * 100) / executable.size
  if problems.isEmpty then
    logInfo m!"ZIL formalization lint passed for '{contract.name}': coverage={coverage}%, \
      level={contract.level.label}, status={contract.status.label}"
  else if contract.status == .satisfied || contract.status == .reviewed then
    throwErrorAt stx
      "ZIL formalization contract '{contract.name}' claims status '{contract.status.label}' \
      but is unsupported:\n{String.intercalate "\n" (problems.toList.map ("- " ++ ·))}"
  else
    logWarning m!"ZIL formalization contract '{contract.name}' remains {contract.status.label}: \
      {problems.toList}"

@[command_elab zilFormalizationLintAllCmd]
meta def elabFormalizationLintAll : CommandElab := fun stx => do
  let env ← getEnv
  let contracts := fileContracts env |>.filter (·.module == env.mainModule)
  if contracts.isEmpty then
    throwErrorAt stx
      "the current module '{env.mainModule}' has no local ZIL formalization contracts"
  let mut failures := #[]
  let mut incomplete := 0
  for contract in contracts do
    let problems := contractProblems env contract
    if problems.isEmpty then
      logInfo m!"ZIL contract passed: {contract.name} ({contract.level.label}, \
        {contract.status.label})"
    else if contract.status == .satisfied || contract.status == .reviewed then
      failures := failures.push
        s!"{contract.name}:\n{String.intercalate "\n" (problems.toList.map ("  - " ++ ·))}"
    else
      incomplete := incomplete + 1
      logWarning m!"ZIL contract remains {contract.status.label}: {contract.name}: \
        {problems.toList}"
  unless failures.isEmpty do
    throwErrorAt stx
      "ZIL aggregate formalization lint failed for module '{env.mainModule}':\n\
      {String.intercalate "\n" failures.toList}"
  logInfo m!"ZIL aggregate formalization lint passed for '{env.mainModule}': \
    contracts={contracts.size}, complete={contracts.size - incomplete}, incomplete={incomplete}"

end Zil.Datalog
