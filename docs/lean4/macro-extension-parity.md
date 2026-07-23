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

```lean
Zil.Parser.MacroProgram.LibrarySource
Zil.Parser.MacroProgram.composeLibraries
Zil.Parser.MacroProgram.parseTextWithLibraries
Zil.Parser.MacroProgram.expandTextWithLibraries
```

Callers provide an ordered array of library sources. The model is appended last. This keeps parsing and expansion native while allowing different filesystem or package managers to supply extension libraries.

## Filesystem workflow

The repository command layer matches `zil.preprocess/preprocess-model`:

1. use `--lib DIR` when supplied;
2. otherwise find the nearest ancestor containing `lib/`;
3. collect only direct `.zc` children;
4. sort them by filename;
5. concatenate them before the model;
6. invoke the native Lean frontend.

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

## Differential parity check

```bash
bin/zil macro-parity model.zc --output macro-parity.edn
```

The command composes the source once, then expands it through:

- `zil.core/expand-macros`;
- `lake exe zil -- expand`.

The check passes only when both ordered expanded statement vectors are exactly equal. The report also includes source SHA-256, library paths, statement counts, frontend-only statements, native exit status, and diagnostics.

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

bin/zil macro-parity \
  examples/macro-extension/model.zc \
  --output /tmp/macro-parity.edn
```
