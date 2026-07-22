# Incremental knowledge deltas

`Zil.Interop.KnowledgeDelta` represents an optimistic, revision-checked change set over a `ZILX` snapshot.

A delta contains:

- base and target revisions;
- added and removed facts;
- added, replaced, and removed rules;
- optional profile changes.

```lean
let updated ← Zil.Interop.applyDelta snapshot delta
```

Application fails when:

- the base revision is stale;
- the target revision does not increase;
- a removed fact is absent;
- a removed rule is absent.

Adjacent deltas can be composed with `composeDelta`. Both Lean and Clojure implement the deterministic `ZILD/1` line protocol.

This is the incremental update layer for long-running agents: a client can retain a snapshot, receive small deltas, and reject stale mutations without rebuilding the full graph.

Lean remains pinned to `leanprover/lean4:v4.31.0`.