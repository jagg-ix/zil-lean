# Legacy `.zc` migration examples

## Lossless migration

The `schwarzschild.zc` file uses facts and a positive single-head rule that map directly to canonical `ZILX/1`.

```bash
mkdir -p build/examples

clojure -M:migrate \
  examples/migration/schwarzschild.zc \
  build/examples/schwarzschild.zilx \
  build/examples/schwarzschild.migration.edn
```

Inspect the generated snapshot with the native Lean CLI:

```bash
lake exe zil -- summary build/examples/schwarzschild.zilx
lake exe zil -- closure build/examples/schwarzschild.zilx

lake exe zil -- query build/examples/schwarzschild.zilx \
  $'rel\tnode:claim.schwarzschildMetric\tzil.requiresClaim\tvar:requirement'
```

The migration report records:

```clojure
{:facts-read 2
 :facts-emitted 2
 :rules-read 1
 :rules-emitted 1
 :queries-skipped 0
 :lossless? true}
```

## Strict rejection of semantic loss

`lossy.zc` contains an attribute and a persisted query. Neither is silently discarded in strict mode:

```bash
clojure -M:migrate \
  examples/migration/lossy.zc \
  build/examples/lossy.zilx \
  build/examples/lossy.migration.edn
```

The command exits unsuccessfully and reports:

```text
:dropped-attributes
:unsupported-query
```

## Explicit audited lossy migration

To retain supported graph knowledge while recording each loss:

```bash
clojure -M:migrate --allow-lossy \
  examples/migration/lossy.zc \
  build/examples/lossy.zilx \
  build/examples/lossy.migration.edn
```

Review the report before accepting the generated snapshot:

```bash
cat build/examples/lossy.migration.edn
```

## Recursive tree migration

Migrate every `.zc` file under a directory while preserving relative paths:

```bash
clojure -M:migrate --tree examples/migration build/migrated
```

For a repository-scale audited pass:

```bash
clojure -M:migrate --allow-lossy --tree lib build/migrated/lib
clojure -M:migrate --allow-lossy --tree libsets build/migrated/libsets
clojure -M:migrate --allow-lossy --tree examples build/migrated/examples
```

Each destination tree contains:

- one `.zilx` snapshot for each successfully migrated `.zc` file;
- one `.migration.edn` report per source file;
- `migration-manifest.edn` summarizing successes and failures.
