module

public import Zil.Datalog.Basic
public import Zil.Datalog.Unify
public import Zil.Datalog.Eval
public import Zil.Datalog.Semantics
public import Zil.Datalog.Model
public import Zil.Datalog.Environment
public meta import Zil.Datalog.Attach
public meta import Zil.Datalog.EmbeddedValidation
public import Zil.Datalog.Tactic.Solve
public import Zil.Datalog.Workflow
public meta import Zil.Datalog.Claim
public meta import Zil.Datalog.FormalizationContract
public import Zil.Datalog.Relation
public import Zil.Datalog.RelationEval
public import Zil.Datalog.RelationEnvironment
public import Zil.Datalog.Revision
public import Zil.Datalog.Index
public import Zil.Datalog.Interop
public import Zil.Datalog.Compat

/-!
# ZIL public root

This root module carries the clause-logic (Datalog) surface used by downstream
Lean libraries: `zil attach`, `zil_claim`/`zil_level` attributes,
`#zil_validate_embedded`, the `zil_solve`/`zil_apply` tactics, and the `Holds`
semantics, all under `Zil.Datalog` with compatibility aliases in `Zil`
(`Zil.Datalog.Compat`).

The native knowledge stack (facts, theorem-shaped rules, engine, provenance,
profiles, authorization) lives in `Zil.Native` and the `Zil.Core`/`Zil.Engine`/
`Zil.Syntax` module trees.
-/
