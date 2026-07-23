# Native compilation of embedded ZIL

ZIL blocks can live beside declarations in Lean, Python, Clojure, Rust, and Markdown files. The embedded compiler extracts each explicit block, resolves its host target, and sends the resulting source through the native Lean frontend.

## Markers

A block starts with `@zil` and ends with `@endzil`.

Lean:

```lean
/-
@zil
self#formalizes@claim:monotone.
self#requires@assumption:positive.
@endzil
-/
theorem Analysis.monotone : True := by trivial
```

Python:

```python
# @zil
# self#purpose@operation:publish.
# @endzil
def publish():
    pass
```

Rust and Clojure use their ordinary line-comment prefixes. Markdown may use plain markers with an explicit target:

```text
@zil target=markdown:architecture
self#documents@concept:authorization.
@endzil
```

## Target resolution

`target=self` attaches the block to the first following supported declaration.

The scanner resolves:

```text
Lean     theorem/def/opaque/axiom/inductive/structure/class/abbrev
Python   def/class
Clojure  defn/defn-/def/defmacro
Rust     fn/struct/enum/trait
```

An explicit target skips declaration lookup:

```text
@zil target=python:publish
```

## Compilation

```bash
clojure -M:embedded-native \
  --root src \
  --root docs \
  --out generated/embedded \
  --manifest generated/embedded/manifest.edn \
  --require-blocks
```

The convenience command is:

```bash
bin/zil-embedded-native --root src --root docs --require-blocks
```

Each block becomes a standalone source unit:

```zc
MODULE embedded.block.embedded_0123456789abcdef.

lean:Analysis.monotone#formalizes@claim:monotone.
lean:Analysis.monotone#requires@assumption:positive.
```

That temporary source is compiled with the equivalent of:

```bash
lake exe zil -- compile block.zc - Zil.Embedded.Src.Analysis.Block0
```

Generated Lean is written atomically.

## Deterministic mapping

For:

```text
src/auth/Policy.lean
```

block ordinal `0` maps to:

```text
generated/embedded/Src/Auth/Policy/Block0.lean
Zil.Embedded.Src.Auth.Policy.Block0
```

Output paths, namespaces, and block identities are checked for collisions before native compilation begins.

## Source maps

`ZIL-EMBEDDED-MANIFEST/1` records:

- absolute host path and selected root;
- root-relative host path;
- host language;
- stable block ID and ordinal;
- resolved target;
- start and end lines;
- source and macro hashes;
- host module, namespace, project, and source-span context;
- standalone source SHA-256;
- generated namespace, output path, hash, and byte count;
- native compiler diagnostics.

This data lets editors and review tools map a generated Lean error back to the host block.

## Macro libraries

Use `--lib` to load the same nearest-library macro environment used by the existing embedded scanner:

```bash
clojure -M:embedded-native --root src --lib lib
```

Host context placeholders remain available:

```text
self file module namespace project revision declaration_kind source_span
```

## Check-only mode

```bash
clojure -M:embedded-native --check --root src
```

The native frontend runs and generated output is hashed, but no `.lean` files are written.

## Failure handling

A scan error is recorded per host file. A native compilation error is recorded per block. Successful blocks remain in the manifest, while the overall result fails when any scan or compile error exists.

`--require-blocks` also fails when the selected roots contain no embedded blocks.

## Validation

```bash
clojure -M:test
clojure -M:embedded-native --root examples/embedded-native --require-blocks
```
