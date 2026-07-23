# Revisioned facts and causal order

The native core supports append-style fact updates, deterministic snapshots, and
an explicit happens-before relation between update events.

## Revision records

```lean
structure RevisionedFact where
  fact : RelExpr
  revision : Nat
  event : Name
  operation : FactOperation
```

Operations are `assert` or `retract`. A logical fact key consists of its subject,
relation, and object. Attributes are the state carried by the latest operation.

This allows a later assertion to replace attributes without creating a second
logical fact.

## Snapshot frontier

`RevisionStore.snapshotAt frontier`:

1. selects records with `revision ≤ frontier`;
2. groups them by logical fact key;
3. keeps the greatest revision for each key;
4. includes the relation only when that operation is `assert`.

A store rejects two operations for the same logical fact at the same revision.

## Causal core

```lean
structure CausalEdge where
  left : Name
  right : Name
```

`left → right` means the left event happens before the right event.

The native graph provides:

```lean
CausalGraph.before
CausalGraph.concurrent
CausalGraph.valid
CausalGraph.addEdge
```

The order is strict:

- an event never precedes itself;
- transitive paths count as happens-before;
- edge insertion rejects cycles;
- two distinct events are concurrent when neither precedes the other.

Revision envelopes require every causal-edge endpoint to name a recorded event.

## Clock overlays

Optional clock structures remain metadata beside the explicit causal graph:

```lean
VectorClock
LamportClock
HybridClock
EventClock
```

Vector clocks use componentwise strict order. Lamport and hybrid clocks expose
their ordinary timestamp order. `EventClock.consistentWith` verifies that
available clock metadata does not reverse an explicit core causal relation.

Clock metadata does not itself insert causal edges.

## Exchange format

`ZILR/1` is a deterministic line-oriented envelope:

```text
ZILR<TAB>1
module<TAB>project.release
record<TAB>1<TAB>event.e1<TAB>assert<TAB><escaped canonical relation>
before<TAB>event.e1<TAB>event.e2
```

Native APIs:

```lean
Zil.Codec.Revision.encodeStore
Zil.Codec.Revision.decodeStore
Zil.Codec.Revision.roundTrips
```

## CLI

```bash
lake exe zil -- revision-summary examples/revision/release.zilr
lake exe zil -- snapshot examples/revision/release.zilr 1
lake exe zil -- snapshot examples/revision/release.zilr 3
lake exe zil -- causal-check examples/revision/release.zilr
```

At revision 1 the status is `open`. At revision 2 it is absent because of the
retraction. At revision 3 the latest assertion carries `state=closed`.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- causal-check examples/revision/release.zilr
```
