# Automated legacy `.zc` migration

The migration tool parses the existing ZIL v0.1 surface, expands macros and standard-library declarations through the current parser, normalizes relation aliases, and emits canonical `ZILX/1` snapshots consumed by the native Lean CLI.

## One file

```bash
clojure -M:migrate input.zc output.zilx output.migration.edn
```

Strict, lossless migration is the default. It rejects:

- negated literals, because the current Lean Horn engine is positive;
- attributes, because `ZILX/1` relations currently carry binary endpoints only;
- persisted queries, because snapshots contain facts and rules rather than query definitions.

A controlled lossy migration must be explicit:

```bash
clojure -M:migrate --allow-lossy input.zc output.zilx output.migration.edn
```

Every dropped or transformed construct is listed in the EDN audit report.

## Recursive repository migration

```bash
clojure -M:migrate --tree lib migrated/lib
clojure -M:migrate --allow-lossy --tree examples migrated/examples
```

The directory structure is preserved. Each `.zc` file produces:

- a `.zilx` canonical snapshot;
- a `.migration.edn` audit report.

The output root also receives `migration-manifest.edn` with deterministic file ordering, success/failure counts, and per-file results. Strict tree migration writes the manifest before failing, so unsupported files can be repaired without losing the complete audit.

Multi-head legacy rules are converted into deterministic single-head rules named `rule__head_N`. Relation aliases such as `requires_claim` normalize to the canonical `zil.requiresClaim` vocabulary.
