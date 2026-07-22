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

private def addImportedKnowledge (states : Array KnowledgeState) : KnowledgeState :=
  states.foldl (init := #[]) fun acc state => acc ++ state

initialize knowledgeExtension : SimplePersistentEnvExtension KnowledgeEntry KnowledgeState ←
  registerSimplePersistentEnvExtension {
    name := `zilKnowledgeExtension
    addEntryFn := fun state entry => state.push entry
    addImportedFn := addImportedKnowledge
  }

/-- Add an entry to the current module and export it through the module's `.olean`. -/
def addEntry (entry : KnowledgeEntry) : CoreM Unit :=
  modifyEnv fun env => knowledgeExtension.addEntry env entry

/-- Read all imported and locally registered ZIL entries. -/
def entries (env : Environment) : KnowledgeState :=
  knowledgeExtension.getState env

/-- Return all persisted graph facts. -/
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

end Zil.Environment
