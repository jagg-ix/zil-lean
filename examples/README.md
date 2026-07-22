# End-to-end examples

These examples exercise the three system-boundary targets together.

## 1. Use a prepared native snapshot

```bash
lake build
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
```

See [`native-cli/README.md`](native-cli/README.md) for checks, queries, exports, and the interactive REPL.

## 2. Migrate legacy `.zc` knowledge

```bash
mkdir -p build/examples

clojure -M:migrate \
  examples/migration/schwarzschild.zc \
  build/examples/schwarzschild.zilx \
  build/examples/schwarzschild.migration.edn
```

The generated snapshot is immediately consumable by the Lean executable:

```bash
lake exe zil -- summary build/examples/schwarzschild.zilx
lake exe zil -- closure build/examples/schwarzschild.zilx
lake exe zil -- export build/examples/schwarzschild.zilx prolog
```

See [`migration/README.md`](migration/README.md) for strict, lossy, and recursive migration.

## 3. Inspect a derivation DAG in Lean

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

The program prints asserted leaves before the derived root and includes the applied rule, binding, trust class, and premise node IDs.

See [`provenance/README.md`](provenance/README.md) for the explanation model and trust boundary.

## Complete validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```

The examples deliberately use one knowledge scenario across all three workflows so the migrated snapshot, native closure, query result, and derivation explanation can be compared directly.
