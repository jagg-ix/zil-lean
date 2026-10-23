# Native macro semantics v0.1

## Surface forms

```text
MACRO name(param1, ..., paramN):
EMIT statement
...
ENDMACRO.

USE name(arg1, ..., argN).
```

## Collection

All macro definitions are collected before payload expansion. Duplicate names,
duplicate parameters, empty bodies, and unterminated definitions are errors.

## Expansion

Each `USE` resolves by exact, case-sensitive source spelling, checks positional
arity, substitutes `{{parameter}}` placeholders using exact parameter spelling,
and recursively expands emitted `USE` statements. Control keywords are
ASCII-case-insensitive and are separated from payload by one or more whitespace
characters.

Macro identifiers are preserved as raw source strings. The parser also retains
the existing normalized Lean `Name` projections on `MacroDef` and
`MacroExpansion` for callers that already use those fields. Macro identity and
substitution never use those normalized projections, so `grant-platform` and
`grant_platform` remain distinct even though older Lean projections may compare
equal.

The expansion result retains the use-site source line and active macro stack.
Expansion stops with an error when:

- a macro is unknown;
- positional arity differs;
- a placeholder remains unresolved;
- a macro name repeats in the active stack;
- the expansion count exceeds 10,000 by default.

## Parser boundary

Macro expansion runs before tuple, rule, query, declaration, and later extension
parsers. Expanded statements therefore use the same canonical IR and runtime as
handwritten source.

## Library composition

For a model composed with a selected macro library directory, imported library
`MODULE` headers are removed because they name standalone library sources, not
the composed compilation unit. The model's `MODULE` is preserved. `--lib DIR`
selects one non-recursive macro library directory; libset source files are not
contaminated with the repository's unrelated default `lib/` directory. Existing
AWS and algebra/theorem extensions therefore use the same Lean macro expansion,
parser, and runtime path as handwritten model statements. This is additive and
does not rename the macros or alter the model's source-language API.

This preserves the current Lean parser and command macro APIs while extending
the source macro path. New macro-generated extension forms must be parsed into
typed Lean IR and pass the same validators as handwritten forms. This contract
does not execute arbitrary Clojure macro code.

## Program data

`Zil.Program` stores the collected definitions and expansion records beside the
expanded tuples, rules, and queries. Macro definitions do not alter semantic
relation equality or rule trust.
