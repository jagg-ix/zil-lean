# Time Core v0.1 (Draft)

## Mandatory Core

`before(e1,e2)` defines a strict partial order.

Axioms:
1. Irreflexive: never `before(e,e)`.
2. Transitive: `before(a,b)` and `before(b,c)` => `before(a,c)`.
3. Acyclic: no cycle in `before`.

`concurrent(e1,e2)` iff neither happens-before the other.

## Optional Profiles

Profiles provide representational clocks, not core semantics:
- `vector_clock`
- `lamport`
- `hybrid_logical_clock`
- `minkowski`

Profile conformance:
1. Must not contradict core causal order.
2. Must be deterministic.
3. Must preserve unknown/incomparable cases when causality is not derivable.

