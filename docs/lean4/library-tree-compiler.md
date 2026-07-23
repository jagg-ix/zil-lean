# Recursive library compilation

The library compiler converts every `.zc` file under one or more directory roots
through the native Lean frontend.

```bash
clojure -M:library \
  --root lib \
  --root libsets \
  --root examples \
  --out generated/zil \
  --manifest generated/zil/manifest.edn
```

The convenience script provides the same command:

```bash
bin/zil-library --root lib --root libsets --root examples
```

## Deterministic mapping

For a source such as:

```text
lib/policy/access-control.zc
```

with namespace prefix `Zil.Generated`, the compiler produces:

```text
generated/zil/Lib/Policy/AccessControl.lean
Zil.Generated.Lib.Policy.AccessControl
```

Source files are sorted by normalized path before compilation. Output paths and
Lean namespaces are derived entirely from the selected root and relative source
path.

The complete plan is checked before the first native compiler process starts.
Duplicate output paths or namespaces stop the operation.

## Native frontend

Each source is compiled with the equivalent of:

```bash
lake exe zil -- compile input.zc - Zil.Generated.Lib.Policy.AccessControl
```

Generated Lean is captured from standard output and written atomically by the
library compiler. A failed source is recorded in the manifest with its exit code
and diagnostic text.

## Manifest

The default manifest is:

```text
generated/zil/manifest.edn
```

Each entry records:

- absolute source, root, and output paths;
- relative source path;
- generated namespace;
- SHA-256 of the source;
- compilation status;
- generated output SHA-256 and byte count;
- native diagnostics for failed entries.

The manifest contains no timestamp, so equal source trees and compiler output
produce equal manifest data.

## Check-only mode

```bash
clojure -M:library --check --root lib --root libsets
```

Check-only mode invokes the native frontend for every source and records output
hashes without writing generated Lean modules.

## Removing stale output

```bash
clojure -M:library --clean-stale --root lib --root libsets
```

After a completely successful compilation, `--clean-stale` removes generated
files that appeared in the previous manifest but no longer appear in the current
plan. Deletion is restricted to the configured output root.

## Custom namespace prefix

```bash
clojure -M:library \
  --namespace Project.Zil \
  --root models \
  --out Generated
```

## Validation

```bash
clojure -M:test
clojure -M:library --check --root lib --root libsets --root examples
```
