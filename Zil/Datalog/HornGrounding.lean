module

public meta import Zil.Datalog.FormalizationContract
public meta import Zil.Horn

/-!
# `#zil_horn_grounding` — a certified grounding check for a ZIL file contract

`#zil_formalization_lint` reports a coverage *percentage* over a contract's
executable requirements.  `#zil_horn_grounding` asks a sharper, structural
question and answers it with the `Zil.Horn` (HORC) definite-Horn engine: does the
contract's `requires_objects` / `witnessed_by` closure actually *bottom out* in
the current environment?

The dependency graph is extracted directly from the live `FileContract` — no
hand transcription:

* a `provided(o)` fact for each `lean:` requirement `o` **that resolves** to a
  declaration in the environment;
* a `witnessed(w)` fact for each witness `w` **that exists** in the environment;
* a single rule `grounded(K) :- provided(o₁), …, witnessed(w₁), …` whose body
  lists *every declared* requirement and witness.

Because the rule body ranges over the declared lists while a fact is emitted only
when the object truly resolves, a dangling `requires_object` or a mistyped /
removed witness leaves its body atom unprovable, so the SLD query
`grounded(K)` fails.  `Zil.Horn.solveCertifiedDepth` accepts an answer only after
independent proof-tree replay, so a reported success is a replay-checked
derivation and not a bare search hit.

Both commands are opt-in, in the style of `#zil_formalization_lint`:

```lean
#zil_horn_grounding my.contract        -- one contract
#zil_horn_grounding_all                -- every contract declared in this module
```
-/

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

private meta def hornGroundingSym (symbol : String) : Zil.Horn.Term := .app symbol []

private meta def hornGroundingAtom (predicate : String)
    (arguments : List Zil.Horn.Term) : Zil.Horn.Atom :=
  { predicate := predicate, arguments := arguments }

private meta def hornGroundingFact (head : Zil.Horn.Atom) : Zil.Horn.Clause := { head := head }

/-- Extract a contract's requires/witness closure as a definite-Horn program and
certify (bounded SLD + independent proof-tree replay) that `grounded(contract)`
holds.  Returns `none` when the contract grounds, otherwise a diagnostic naming
the unmet obligations. -/
meta def hornGroundingProblem? (env : Environment) (contract : FileContract) : Option String :=
  let leanRequirements := contract.requirements.filter (·.startsWith "lean:")
  let nonLeanRequirements := contract.requirements.filter (! ·.startsWith "lean:")
  let requirementResolves := fun (requirement : String) =>
    (env.find? (requirement.drop 5).toName).isSome
  let witnessResolves := fun (witness : Name) => (env.find? witness).isSome
  let providedFacts := leanRequirements.filterMap fun requirement =>
    if requirementResolves requirement then
      some (hornGroundingFact (hornGroundingAtom "provided" [hornGroundingSym requirement]))
    else none
  let witnessedFacts := contract.witnesses.filterMap fun witness =>
    if witnessResolves witness then
      some (hornGroundingFact (hornGroundingAtom "witnessed" [hornGroundingSym witness.toString]))
    else none
  let requirementBody := leanRequirements.toList.map fun requirement =>
    hornGroundingAtom "provided" [hornGroundingSym requirement]
  let witnessBody := contract.witnesses.toList.map fun witness =>
    hornGroundingAtom "witnessed" [hornGroundingSym witness.toString]
  let contractSymbol := hornGroundingSym contract.name.toString
  let groundingRule : Zil.Horn.Clause :=
    { head := hornGroundingAtom "grounded" [contractSymbol]
      body := requirementBody ++ witnessBody }
  let program : Zil.Horn.Program :=
    providedFacts.toList ++ witnessedFacts.toList ++ [groundingRule]
  let query : List Zil.Horn.Atom := [hornGroundingAtom "grounded" [contractSymbol]]
  let bound := 16 + 2 * (leanRequirements.size + contract.witnesses.size)
  if (Zil.Horn.solveCertifiedDepth program query bound).solutions.isEmpty then
    let missingRequirements := leanRequirements.filter (! requirementResolves ·)
    let missingWitnesses := contract.witnesses.filter (! witnessResolves ·)
    some s!"no certified derivation of grounded({contract.name}); \
      missing lean requirements: {missingRequirements.toList}; \
      missing witnesses: {missingWitnesses.toList}; \
      unverifiable non-lean requirements: {nonLeanRequirements.toList}"
  else
    none

syntax (name := zilHornGroundingCmd) "#zil_horn_grounding " ident : command
syntax (name := zilHornGroundingAllCmd) "#zil_horn_grounding_all" : command

@[command_elab zilHornGroundingCmd]
meta def elabZilHornGrounding : CommandElab := fun stx => do
  let `(#zil_horn_grounding $name:ident) := stx | throwUnsupportedSyntax
  let env ← getEnv
  let some contract := fileContract? env name.getId
    | throwErrorAt name m!"no ZIL file contract named '{name.getId}'"
  match hornGroundingProblem? env contract with
  | some diagnostic =>
    throwErrorAt stx m!"ZIL Horn grounding FAILED for '{contract.name}': {diagnostic}"
  | none =>
    let leanRequirements := contract.requirements.filter (·.startsWith "lean:")
    logInfo m!"ZIL Horn grounding CERTIFIED for '{contract.name}': grounded({contract.name}) has a \
      replay-checked derivation ({leanRequirements.size} lean requirement(s) + \
      {contract.witnesses.size} witness(es))."

@[command_elab zilHornGroundingAllCmd]
meta def elabZilHornGroundingAll : CommandElab := fun stx => do
  let env ← getEnv
  let contracts := fileContracts env |>.filter (·.module == env.mainModule)
  if contracts.isEmpty then
    throwErrorAt stx
      m!"the current module '{env.mainModule}' has no local ZIL formalization contracts"
  let mut failures : Array String := #[]
  for contract in contracts do
    match hornGroundingProblem? env contract with
    | some diagnostic => failures := failures.push s!"{contract.name}: {diagnostic}"
    | none => logInfo m!"ZIL Horn grounding certified: {contract.name}"
  unless failures.isEmpty do
    throwErrorAt stx
      m!"ZIL Horn grounding failed for module '{env.mainModule}':\n\
        {String.intercalate "\n" failures.toList}"
  logInfo m!"ZIL Horn grounding certified for all {contracts.size} local contract(s) in \
    '{env.mainModule}'."

end Zil.Datalog
