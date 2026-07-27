module

public import Zil.Datalog.Basic
public import Zil.Datalog.Semantics
public import Zil.Datalog.Model
public import Zil.Datalog.Environment

/-!
# Compatibility aliases for the clause-logic surface

Some downstream code predates the `Zil.Datalog` namespace and refers to the
clause-logic core as `Zil.Value`, `Zil.Program`, `Holds`, and so on. These
aliases keep that surface stable. The native knowledge stack keeps its own
`Zil.Term`/`Zil.Rule`/`Zil.Program`; the two never load into the same
environment through this root, so the aliases stay unambiguous.
-/

@[expose] public section

namespace Zil

export Datalog (Value Term Atom Literal Pattern Rule Program Substitution
  AtomAttrs PatternAttrs RelationStrata RuleDependency RuleDependencyPolarity
  Holds Derives Interpretation IsStratifiedModel RuleConsequence)

end Zil
