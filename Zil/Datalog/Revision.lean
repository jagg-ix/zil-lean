module

public import Lean

@[expose] public section

open Lean

namespace Zil.Datalog

/-- Whether a frozen knowledge input claims to contain its full declared scope. -/
inductive SnapshotCompleteness where
  | complete
  | partialSnapshot
  | unspecified
  deriving Repr, DecidableEq, Inhabited

/-- One immutable identity shared by Datalog snapshots, relation tuple stores,
schemas, and the Lean module environment that admitted the knowledge. The
`token` and `schemaVersion` names intentionally preserve source compatibility
with the original relation-layer `Revision`. -/
structure KnowledgeRevision where
  token : String
  schemaProfile : Name := `default
  schemaVersion : Nat := 1
  completeness : SnapshotCompleteness := .unspecified
  environment : Name := `unknown
  deriving Repr, DecidableEq, Inhabited

def KnowledgeRevision.withSchema (revision : KnowledgeRevision)
    (profile : Name) (version : Nat) : KnowledgeRevision :=
  { revision with schemaProfile := profile, schemaVersion := version }

def KnowledgeRevision.withEnvironment (revision : KnowledgeRevision)
    (environment : Name) : KnowledgeRevision :=
  { revision with environment }

def KnowledgeRevision.snapshot (token : String) (completeness : SnapshotCompleteness)
    (environment : Name := `unknown) : KnowledgeRevision :=
  { token, completeness, environment }

/-- Compatibility name used by the initial Zanzibar relation API. -/
abbrev Revision := KnowledgeRevision

end Zil.Datalog
