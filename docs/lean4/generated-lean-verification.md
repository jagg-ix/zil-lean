# Generated Lean verification

The recursive library compiler proves that each `.zc` source can be translated into Lean text. The generated verifier checks the next boundary: every generated module must elaborate successfully, and all generated modules must be importable together.

## Workflow

```bash
clojure -M:library \
  --root lib \
  --root libsets \
  --root examples

clojure -M:verify-generated
```

The convenience command is:

```bash
bin/zil-verify-generated
```

The verifier reads:

```text
generated/zil/manifest.edn
```

and writes:

```text
generated/zil/verification.edn
generated/zil/All.lean
```

## Checks

For every manifest entry, the verifier checks:

1. the source was compiled or checked by the native frontend;
2. the generated `.lean` file exists;
3. its SHA-256 matches the compiler manifest;
4. `lake env lean <generated-file>` succeeds.

Hash validation runs before Lean. A modified or stale generated file is reported as `:hash-mismatch` and is not elaborated.

## Aggregate import

After all individual modules pass, the verifier creates a deterministic aggregate module:

```lean
import Zil.Generated.Examples.Access
import Zil.Generated.Lib.Policy.Authorization
import Zil.Generated.Libsets.Core.Relations
```

Imports are sorted and deduplicated. The generated output root is added to `LEAN_PATH`, then the aggregate module is elaborated.

This catches failures that individual file checks do not expose, including:

- duplicate declarations across generated modules;
- incompatible namespace content;
- missing generated imports;
- environment-extension reconstruction failures;
- import-order assumptions.

Aggregate verification is blocked when any individual module fails.

## Result states

Individual modules use:

```text
:verified
:missing
:hash-mismatch
:failed
:skipped
```

The aggregate uses:

```text
:verified
:failed
:blocked
:skipped
```

A report passes only when every manifest entry is `:verified` and the aggregate is `:verified` or explicitly disabled.

## Options

```bash
clojure -M:verify-generated \
  --manifest generated/zil/manifest.edn \
  --output generated/zil/verification.edn \
  --aggregate generated/zil/All.lean
```

To verify individual modules without creating the aggregate:

```bash
clojure -M:verify-generated --no-aggregate
```

## Validation

```bash
clojure -M:test
clojure -M:verify-generated
```
