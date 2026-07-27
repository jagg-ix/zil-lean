# ZIL examples

Every documented example group is runnable through the Makefile:

```bash
make examples                 # lean, native, integration, and legacy groups
make examples GROUP=lean      # or: make examples-lean, examples-native,
                              #     examples-integration, examples-legacy
```

The runner executes exactly the commands documented in each example's header,
writes a `ZIL-EXAMPLES-REPORT/1` TSV to `.zil/examples-reports/<group>-latest.tsv`
with per-step logs beside it, and records steps whose toolchain is missing
(for example the legacy Clojure runtime) as skips rather than failures.
Assertion-level checks for several of the same models live in the standalone
`tools/*_smoke.sh` scripts.

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
2. theorem-shaped rules;
3. typed schema validation;
4. multi-step rule evaluation and queries;
5. stored relationships across Lean imports.

See [`lean/README.md`](lean/README.md) for the complete guide.

## Original tuple syntax to Lean

The tuple exporter accepts the original ZIL syntax directly:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
```

Generate native `zil_fact` declarations and userset rules with:

```bash
clojure -M:tuple-lean \
  examples/tuple-lean/access.zc \
  examples/tuple-lean/Access.lean \
  Zil.Generated.Access
```

See [`tuple-lean/README.md`](tuple-lean/README.md).

## Additional examples

The native CLI example drives a small formalization-claims model:

```bash
bin/zil expand examples/native-cli/formalization-claims.zc -
bin/zil query-ci examples/native-cli/formalization-claims.zc
```

See [`native-cli/README.md`](native-cli/README.md).

The relationship-explanation example displays how a derived fact was produced:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

See [`provenance/README.md`](provenance/README.md).

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```
