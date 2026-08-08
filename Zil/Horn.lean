module

public import Zil.Horn.Basic
public import Zil.Horn.Unify
public import Zil.Horn.Resolution
public import Zil.Horn.Certificate
public import Zil.Horn.Completeness
public import Zil.Horn.Parser
public import Zil.Horn.Tactic.Solve

/-!
# ZIL Horn

First-order definite Horn clauses for ZIL: constructor terms, sound unification
with an occurs check, leftmost SLD resolution, clause-order backtracking,
depth-bounded search, iterative deepening for a first solution, proof-facing
semantics, sound and complete proof-tree reflection, and a parser for the pure
Prolog notation used by HORC `.hn` files.

This is a separate layer from `Zil.Datalog`: existing finite bottom-up workloads
keep their fixed-point engine, while Horn programs opt into potentially infinite
terms and top-down proof search explicitly.
-/
