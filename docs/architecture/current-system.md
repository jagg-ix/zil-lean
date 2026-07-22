# Current system inventory

This document records the existing implementation surfaces that must be reused rather than duplicated by the Lean-native work.

## Runtime and language core

- Clojure parser, lowering, macro expansion, rule evaluation, and query planning.
- DataScript runtime for immutable snapshots, indexed facts, Datalog queries, recursive rules, and stratified negation patterns.
- SQLite persistence for Lean event deltas, workflow state, leases, checkpoints, and action records.

## Existing Lean-facing bridges

- Lean source export.
- Lean event import and delta publication.
- Snapshot export to Lean.
- Workflow-state export to Lean.
- Theorem and proof-obligation bridges.
- Formalization target checking.

## Embedded source support

The current embedded scanner already supports marked ZIL blocks in Lean, Python, Clojure, and Rust source. It resolves `self`, records source spans and hashes, expands pure ZIL macros, and supports drift snapshots.

## Agent-safety support

The CLI already exposes context preflight, scope grants, leases, checkpoints, action preflight, action recording, action verification, and drift analysis. The Lean-native work should connect these mechanisms to formalization contracts rather than introduce a second safety subsystem.

## Architectural rule for the PR series

The implementation should converge on one canonical relational IR consumed by:

1. standalone `.zc` parsing;
2. embedded comment scanning;
3. Lean-native syntax;
4. query planning;
5. rule analysis;
6. formalization lint;
7. Lean export and environment extensions.

No new frontend should create a parallel semantic representation.
