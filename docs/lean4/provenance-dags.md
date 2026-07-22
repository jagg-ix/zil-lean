# Provenance-rich derivation DAGs

`Zil.Engine.Provenance.build` computes closure while recording a cycle-free derivation graph.

Each node stores:

- a stable node ID;
- the semantic fact;
- whether it was asserted or rule-derived;
- the exact rule name;
- the variable binding used by that rule;
- the rule trust class;
- premise edges to earlier nodes.

```lean
let dag := Zil.Engine.Provenance.build facts rules
let some root := Zil.Engine.Provenance.rootFor? dag target | failure
let explanation := Zil.Engine.Provenance.explain dag root
```

The first derivation of each semantic fact is retained, which keeps the graph acyclic and deterministic. `explain` returns a topological subtree from asserted leaves to the requested fact.

This is graph provenance only. It does not create Lean proof terms or change trust.
