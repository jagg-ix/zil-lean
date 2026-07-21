# Zil v0.1r1 (Draft)

## Scope

Zil defines a declarative language for facts, rules, constraints, and queries.
It is implementation-agnostic and Datalog-first in semantics.

## Domain Positioning

The core language is domain-agnostic.

Domain-specific declaration sets (including current IT-oriented declarations)
are optional layers that must lower into equivalent canonical core semantics.
They do not alter core correctness criteria.

## Core Language Boundaries

Core includes:
- tuple model: `object#relation@subject [attrs]`
- module/namespace declarations
- rules and stratified negation
- constraints and aggregation semantics
- revisioned snapshots and causal ordering semantics

Core excludes:
- host language syntax
- runtime side-effect behavior
- backend-specific storage/engine mechanics

See also `docs/language-architecture.md` for the layered architecture view.

## Time Model

- Mandatory core: causal partial order over events.
- Optional profiles: vector clocks, hybrid clocks, relativistic coordinate profiles.
- Core queries operate on causal frontiers.

See `spec/time-core-v0.1.md`.

## Conformance (high-level)

An implementation is conformant if it:
1. Accepts canonical surface syntax.
2. Produces equivalent canonical IR.
3. Evaluates rules to least-fixpoint under stratified negation.
4. Preserves snapshot semantics at specified frontiers/revisions.

Concrete backend conformance profiles may define operational mappings.
First profile: `spec/runtime-datascript-profile-v0.1.md`.
