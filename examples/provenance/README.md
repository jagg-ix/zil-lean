# Provenance DAG example

`DerivationDAG.lean` derives one claim requirement from two asserted facts and prints the complete explanation in topological order.

Run it with the repository toolchain:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

The explanation contains three nodes:

1. the asserted `formalizes` fact;
2. the asserted `requires` fact;
3. the derived `requiresClaim` fact.

The root node records:

- rule name `schwarzschildClaimRequirement`;
- the concrete variable binding;
- `.graphDerived` trust;
- premise node IDs pointing to both asserted leaves.

The DAG is graph provenance only. It is not a Lean proof of the represented scientific claim.
