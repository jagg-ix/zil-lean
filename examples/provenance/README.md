# Provenance DAG example

This example is the advanced continuation of the native Lean learning path in
[`../lean/README.md`](../lean/README.md).

Run it with:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

The program constructs two asserted facts and one graph rule, builds the
least-fixpoint derivation DAG, locates the derived requirement fact, and prints a
topologically ordered explanation.

Each printed node includes:

- its stable numeric identifier;
- the canonical relation;
- whether it was asserted or derived;
- the rule and concrete variable binding for derived nodes;
- the graph trust class;
- premise node identifiers.

The resulting shape is:

```text
asserted formalizes fact ─┐
                          ├─ propagateRequirement ─ derived requiresClaim fact
asserted requires fact ───┘
```

The DAG is graph provenance only. It does not create a Lean proof term and does
not discharge a Lean theorem.
