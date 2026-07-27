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

Each `USE` resolves by exact macro name, checks positional arity, substitutes
`{{parameter}}` placeholders, and recursively expands emitted `USE` statements.

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

## Program data

`Zil.Program` stores the collected definitions and expansion records beside the
expanded tuples, rules, and queries. Macro definitions do not alter semantic
relation equality or rule trust.
