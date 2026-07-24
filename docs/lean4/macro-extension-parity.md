# Macro-based extension parity

The native Lean frontend supports the language-level macro extension model used by the original Clojure implementation.

## Macro syntax

```zc
MACRO grant(object, relation, subject):
  EMIT {{object}}#{{relation}}@{{subject}}.
ENDMACRO.

USE grant(doc:readme, viewer, user:11).
```

The control keywords are case-insensitive:

```text
MACRO
EMIT
ENDMACRO
USE
```

Macro names and parameter names remain case-sensitive, matching the original implementation.

## Supported extension capabilities

| Capability | Clojure | Native Lean |
|---|---:|---:|
| Positional parameters | Yes | Yes |
| Multiple `EMIT` statements | Yes | Yes |
| `{{parameter}}` substitution | Yes | Yes |
| Nested `USE` expansion | Yes | Yes |
| Quoted and nested arguments | Yes | Yes |
| Facts emitted by macros | Yes | Yes |
| Rules emitted by macros | Yes | Yes |
| Queries emitted by macros | Yes | Yes |
| Typed declarations emitted by macros | Yes | Yes |
| Case-insensitive control keywords | Yes | Yes |
| Inline `//` comments outside strings | Yes | Yes |
| `//` preserved inside quoted strings | Yes | Yes |
| 10,000-expansion safety bound | Yes | Yes |
| Sorted non-recursive `lib/*.zc` composition | Yes | Yes |
| Explicit library directory | Yes | Yes |
| Nearest ancestor `lib/` discovery | Yes | Yes |

The native frontend additionally records expansion stacks and source lines, rejects unresolved placeholders, and detects direct recursive cycles before consuming the full expansion limit.

## Native source composition API

Semantic programs:

```lean
Zil.Parser.MacroProgram.LibrarySource
Zil.Parser.MacroProgram.composeLibraries
Zil.Parser.MacroProgram.parseTextWithLibraries
Zil.Parser.MacroProgram.expandTextWithLibraries
```

Typed declaration programs:

```lean
Zil.Parser.DeclarationProgram.parseTextWithLibraries
```

Callers provide an ordered array of library sources. The model is appended last. The declaration-aware entry point allows library macros to emit tuples, usersets, rules, queries, and every supported typed declaration.

## Filesystem workflow

The Clojure control plane matches `zil.preprocess/preprocess-model`:

1. use `--lib DIR` when supplied;
2. otherwise find the nearest ancestor containing `lib/`;
3. collect only direct `.zc` children;
4. sort them by filename;
5. concatenate them before the model;
6. submit the exact prepared bytes to the Lean `compile` or `expand` exchange capability.

Compile with macro libraries:

```bash
bin/zil macro-compile model.zc \
  --output Generated.lean \
  --namespace Project.Generated
```

Expand only:

```bash
bin/zil macro-expand model.zc --output expanded.zc
```

Select an explicit library:

```bash
bin/zil macro-compile model.zc --lib path/to/lib
```

Direct files inside the selected `lib/` directory remain standalone. They are never prepended to themselves.

## Formal control-plane boundary

The public macro aliases route through `zil.control.adapters`.

Clojure remains authoritative for:

- library discovery;
- source composition;
- temporary-file lifecycle;
- output placement;
- differential comparison.

Lean remains authoritative for:

- macro expansion semantics;
- declaration parsing;
- generated module bytes;
- native conformance rows.

The low-level `zil.port.native-macro` runner hook remains injectable for unit tests and explicit external verification. It is not the default public semantic path.

## Differential parity check

```bash
bin/zil macro-parity model.zc --output macro-parity.edn
```

The command composes the source once, then expands it through:

- `zil.core/expand-macros` as the compatibility oracle;
- the Lean `expand-v1` operation over `ZIL-EXCHANGE/1`.

The check passes only when both ordered expanded statement vectors are exactly equal. The report also includes source SHA-256, library paths, statement counts, frontend-only statements, native status, and diagnostics.

## Corpus compilation and conformance

The recursive library compiler and differential conformance harness use the same prepared-source function as the direct macro commands.

For a model backed by a nearest or explicit macro library, manifest and conformance entries record:

```text
source-sha256
compiled-source-sha256
macro-composed
lib-dir
lib-files
```

The raw source hash identifies the model file. The compiled-source hash identifies the exact concatenated library-plus-model input supplied to both frontends.

The conformance harness compiles and expands the same prepared text on both sides. Native semantic rows come from the Lean `conformance-v1` capability. A valid library-backed model can no longer appear as a misleading shared rejection caused by an unresolved macro invocation.

The port gate requires exact parity for macro-bearing corpus sources and checks that the native parser, library API, formal control-plane adapter, tests, and parity specification remain present.

## Comments and strings

This line loses only the trailing comment:

```zc
EMIT doc:readme#meta@value:item [url="https://example/a//b"]. // note
```

The `//` inside the quoted URL remains part of the string.

## Scope

Macros are source-to-source extensions. They do not execute Clojure or Lean metaprograms and cannot bypass native declaration, rule-safety, stratification, or type checks. Expanded statements enter the ordinary ZIL parser and engine.

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test

bin/zil library --check \
  --root lib --root libsets --root examples

bin/zil conformance-suite \
  --root lib --root libsets --root examples

bin/zil macro-parity \
  examples/macro-extension/model.zc \
  --output /tmp/macro-parity.edn
```
