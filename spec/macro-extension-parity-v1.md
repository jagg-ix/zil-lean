# ZIL macro extension parity v1

## Control syntax

```text
MACRO <name>(<parameters>):
EMIT <source statement>
ENDMACRO.
USE <name>(<arguments>).
```

`MACRO`, `EMIT`, `ENDMACRO`, and `USE` are ASCII case-insensitive. Macro and parameter identifiers remain case-sensitive.

## Parameters and arguments

- Parameters are positional.
- Parameter names are unique inside one macro.
- Invocation arity equals definition arity.
- Comma splitting respects quoted strings and nested `()`, `[]`, and `{}` delimiters.
- Substitution replaces `{{parameter}}` with the original argument text.
- Unresolved `{{...}}` placeholders are rejected by the native frontend.

## Expansion

- A macro contains one or more `EMIT` lines.
- Emitted statements are reprocessed for nested `USE` invocations.
- Expansion is depth-first and preserves emitted statement order.
- At most 10,000 macro invocations may be expanded per source unit.
- The native frontend rejects direct or indirect recursive cycles and records the expansion stack.
- Expansion occurs before tuple, declaration, rule, and query parsing.

Therefore macros may generate:

```text
tuples
userset tuples
rules
queries
typed declarations
other macro uses
```

Expanded statements remain subject to ordinary parser, declaration, rule-safety, stratification, and generated-Lean checks.

## Lexical comments

`//` starts a line comment only outside a double-quoted string. Backslash escapes inside strings are retained. Blank and comment-only lines are removed before macro collection.

## Native library composition

```lean
structure LibrarySource where
  label : String
  text : String

composeLibraries : Array LibrarySource → String → String → String
parseTextWithLibraries : Array LibrarySource → String → String → Nat → Except ParseError Program
expandTextWithLibraries : Array LibrarySource → String → String → Nat → Except ParseError String
```

Library order is caller-controlled. The model is appended after every library source.

## Filesystem composition

The command adapter uses the existing Clojure-compatible resolution rule:

1. explicit `--lib DIR`, when present;
2. otherwise the nearest ancestor directory named `lib`;
3. direct child files ending in `.zc` only;
4. lexicographic filename order;
5. libraries before the model.

The search is non-recursive.

## Commands

```text
bin/zil macro-compile <model.zc> [--output FILE|-] [--namespace NAME] [--lib DIR]
bin/zil macro-expand <model.zc> [--output FILE|-] [--lib DIR]
bin/zil macro-parity <model.zc> [--output FILE|-] [--lib DIR]
```

`macro-compile` and `macro-expand` invoke the native Lean frontend over one composed temporary source file.

## Parity report

```clojure
{:schema "ZIL-MACRO-PARITY/1"
 :ok true
 :model "/absolute/model.zc"
 :lib_dir "/absolute/lib"
 :lib_files ["/absolute/lib/10-base.zc"]
 :source_sha256 "..."
 :legacy_count 5
 :native_count 5
 :exact true
 :legacy_only []
 :native_only []
 :native_exit 0
 :native_error ""
 :native_command [...]}
```

`:ok` is true exactly when native expansion exits zero and the ordered normalized statement vector equals `zil.core/expand-macros` output.

## Compatibility and stronger checks

The native implementation intentionally adds checks that do not reduce valid extension capability:

- explicit unresolved-placeholder rejection;
- immediate recursive-cycle diagnostics;
- source line and expansion-stack retention;
- native program validation after expansion.
