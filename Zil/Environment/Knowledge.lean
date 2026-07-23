import Lean
import Zil.Core.Relation
import Zil.Core.Rule
import Zil.Profile.Core

namespace Zil.Environment

open Lean

/-- Persisted entries exported through `.olean` files. -/
inductive KnowledgeEntry where
  | fact : Zil.RelExpr → KnowledgeEntry
  | rule : Zil.Rule → KnowledgeEntry
  | profile : Zil.Profile → KnowledgeEntry
  | declarationLink : Name → Zil.RelExpr → KnowledgeEntry
  deriving Repr, Inhabited

abbrev KnowledgeState := Array KnowledgeEntry

namespace KnowledgeEntry

/-- Semantic equality used while combining imported module states.
Source locations do not make graph facts distinct. -/
def semanticallyEqual : KnowledgeEntry → KnowledgeEntry → Bool
  | .fact left, .fact right => left.semanticallyEqual right
  | .rule left, .rule right => left.name == right.name
  | .profile left, .profile right =>
      left.name == right.name && left.version == right.version
  | .declarationLink leftName leftRel,
      .declarationLink rightName rightRel =>
      leftName == rightName && leftRel.semanticallyEqual rightRel
  | _, _ => false

end KnowledgeEntry

private def pushUnique (state : KnowledgeState) (entry : KnowledgeEntry) : KnowledgeState :=
  if state.any (KnowledgeEntry.semanticallyEqual entry) then state else state.push entry

private def addImportedKnowledge (states : Array KnowledgeState) : KnowledgeState :=
  states.foldl (init := #[]) fun acc state =>
    state.foldl (init := acc) pushUnique

initialize knowledgeExtension : SimplePersistentEnvExtension KnowledgeEntry KnowledgeState ←
  registerSimplePersistentEnvExtension {
    name := `zilKnowledgeExtension
    addEntryFn := pushUnique
    addImportedFn := addImportedKnowledge
  }

/-- Add an entry to the current module and export it through the module's `.olean`. -/
def addEntry (entry : KnowledgeEntry) : CoreM Unit :=
  modifyEnv fun env => knowledgeExtension.addEntry env entry

/-- Read all imported and locally registered ZIL entries. -/
def entries (env : Environment) : KnowledgeState :=
  knowledgeExtension.getState env

/-- Return all persisted graph facts, including facts attached to declarations. -/
def facts (env : Environment) : Array Zil.RelExpr :=
  (entries env).filterMap fun
    | .fact fact => some fact
    | .declarationLink _ fact => some fact
    | _ => none

/-- Return all persisted graph rules. -/
def rules (env : Environment) : Array Zil.Rule :=
  (entries env).filterMap fun
    | .rule rule => some rule
    | _ => none

/-- Return all persisted profiles. -/
def profiles (env : Environment) : Array Zil.Profile :=
  (entries env).filterMap fun
    | .profile profile => some profile
    | _ => none

/-- Return relation metadata attached to one Lean declaration. -/
def linksForDeclaration (env : Environment) (declaration : Name) : Array Zil.RelExpr :=
  (entries env).filterMap fun
    | .declarationLink name relation =>
        if name == declaration then some relation else none
    | _ => none

/-- Test whether a semantic fact is present in the environment. -/
def containsFact (env : Environment) (target : Zil.RelExpr) : Bool :=
  (facts env).any fun fact => fact.semanticallyEqual target

/-- Test whether a rule with the given canonical name is present. -/
def containsRule (env : Environment) (name : Name) : Bool :=
  (rules env).any fun rule => rule.name == name

/-- Test whether a profile name and version are present. -/
def containsProfile (env : Environment) (name : Name) (version : String) : Bool :=
  (profiles env).any fun profile =>
    profile.name == name && profile.version == version

end Zil.Environment