# ZIL examples

The primary learning path is written directly in Lean:

```text
examples/lean/
```

Start with:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
```

Then continue in numeric order through:

1. facts and native relations;
2. theorem-shaped graph rules;
3. typed profile validation;
4. multi-step closure and queries;
5. persistent knowledge across Lean imports.

See [`lean/README.md`](lean/README.md) for the complete guide.

## Additional examples

The native CLI example uses a prepared canonical snapshot:

```bash
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
```

See [`native-cli/README.md`](native-cli/README.md).

The provenance example displays the explanation DAG for a derived fact:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

See [`provenance/README.md`](provenance/README.md).

## Validation

```bash
lake build
lake exe zilLeanTests
```

These examples use the native Lean implementation. No `.zc` migration step is
required.
