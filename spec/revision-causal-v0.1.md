# Revision and causal core v0.1

## Revision state

A revision record contains a ground relation, natural-number revision, event
identifier, and assert/retract operation.

For a frontier `r`, snapshot materialization keeps the maximum revision not
greater than `r` for each `(subject, relation, object)` key and includes that
relation exactly when the maximum operation is `assert`.

Two records with one key and one revision are invalid.

## Causal order

The primitive relation is `before(e1,e2)`, represented by explicit directed
edges and interpreted by transitive closure.

A valid graph is irreflexive and acyclic. `concurrent(e1,e2)` holds for distinct
events exactly when neither `before(e1,e2)` nor `before(e2,e1)` is derivable.

## Clock metadata

Vector, Lamport, and hybrid logical clocks are optional overlays. They can be
checked against explicit causal edges but do not redefine the causal relation.

## Envelope

`ZILR/1` contains one module row, revision-record rows, and causal-edge rows.
Canonical relations are escaped inside record rows. Decoding rejects malformed
rows, invalid facts, duplicate key/revision operations, cycles, and edges that
name unknown events.

## Conformance

A conforming implementation:

1. validates ground revision records;
2. materializes snapshots by latest-operation semantics;
3. computes transitive happens-before;
4. rejects causal cycles;
5. reports concurrency from incomparability;
6. keeps clock overlays separate from core causal truth;
7. round-trips valid `ZILR/1` envelopes deterministically.
