# ZIL macro extensions v1

## Control syntax

```text
MACRO <name>(<parameters>):
EMIT <source statement>
ENDMACRO.
USE <name>(<arguments>).
```

`MACRO`, `EMIT`, `ENDMACRO`, and `USE` are ASCII case-insensitive. One or more whitespace characters separate a control keyword from its payload. Macro and parameter identifiers remain case-sensitive source strings; parsing them must not apply tuple-name normalization (`-` to `_`, `:` or `/` to namespace separators, or numeric-prefix rewriting).

Macro names use `[A-Za-z0-9_.:-]+`. Parameter names use `[A-Za-z_][A-Za-z0-9_:\-.]*`. These are source-language identifiers, not Lean identifiers. The native implementation retains its historical `Name` fields for existing Lean callers and stores the raw source spelling alongside them. Raw spelling is authoritative for macro lookup, duplicate detection, recursion detection, parameter binding, and placeholder substitution.

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

Expansion is a source transformation, not a second runtime. It may emit any statement accepted by the ZIL parser, including tuples, usersets, rules, queries, typed declarations, and nested macro uses. Each emitted statement then passes through the ordinary Lean parser and validators. New statement extensions are ported by adding their typed parser/IR and conformance cases; macro expansion itself does not grant an extension execution or authority capability.

When a model imports a macro library, the library's `MODULE` header is standalone-file metadata and is omitted during composition; the model's own `MODULE` is retained as the sole compilation-unit name. Macro library directories are selected explicitly with `--lib DIR` (for example `libsets/aws-model` or `libsets/theorem-dsl-ci`) or discovered through the documented nearest `lib/` rule. A libset is not implicitly mixed with unrelated root libraries. This allows existing algebra/theorem and AWS macro sources to run through the native Lean expander without changing their source spelling or the model's identity.

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

MacroProgram.composeLibraries
MacroProgram.parseTextWithLibraries
MacroProgram.expandTextWithLibraries
DeclarationProgram.parseTextWithLibraries
```

Library order is caller-controlled. The model is appended after every library source. `DeclarationProgram.parseTextWithLibraries` retains typed declarations emitted by extension macros.

## Filesystem composition

The command line resolves a library with this rule:

1. explicit `--lib DIR`, when present;
2. otherwise the nearest ancestor directory named `lib`;
3. direct child files ending in `.zc` only;
4. lexicographic filename order;
5. libraries before the model.

The search is non-recursive. A file that is itself a direct member of the selected library remains standalone and is not prepended to itself. A selected library with no `.zc` files leaves the model source unchanged.

## Commands

```text
bin/zil compile <model.zc> [output.lean|-] [namespace] [--lib DIR]
bin/zil expand <model.zc> [output.zc|-] [--lib DIR]
```

Both invoke the native Lean frontend over the model with its library prepended. Without `--lib` the model is read alone.

## Qualification

`tools/macro_extension_matrix.sh` runs every row of `spec/macro-extension-matrix.tsv`: the native expansion must equal the reviewed golden in `spec/macro-extension-golden/`, the model must compile natively, and the generated Lean must typecheck. `bin/zil corpus` compiles every source alone and compares the outcome with `spec/corpus-status.tsv`. A library-backed model must expand with its library; an unresolved macro invocation is not accepted as evidence.

## Checks

The native implementation checks, without reducing valid extension capability:

- explicit unresolved-placeholder rejection;
- immediate recursive-cycle diagnostics;
- source line and expansion-stack retention;
- native program validation after expansion.

Existing Lean APIs and command forms remain source-compatible. In particular, `MacroDef.name`, `MacroDef.parameters`, and `MacroExpansion.macroName` continue to expose their existing normalized `Name` values; raw source names are additive metadata. The separate Lean command-level `zil_macro` / `zil_use` elaborator remains supported and is not silently reinterpreted as the `.zc` macro language.

Future macro extensions should use the same pipeline: define a versioned source form, lower it into typed Lean syntax or ZIL IR, validate it with the existing kernel/parser boundary, and add positive and negative conformance cases. Arbitrary code evaluation is not implied by a `.zc` macro and is outside this language contract.
