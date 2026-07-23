# Native source macros

ZIL source files can define reusable statement templates and expand them before
tuple, rule, and query parsing.

```zc
MACRO grant(object, group):
EMIT {{object}}#viewer@{{group}}#member.
ENDMACRO.

MACRO grantPlatform(object):
EMIT USE grant({{object}}, group:platform).
ENDMACRO.

group:platform#member@user:11.
USE grantPlatform(doc:readme).
```

The expanded tuple is:

```zc
doc:readme#viewer@group:platform#member.
```

The standard userset lowering then produces the stored group relation and the
viewer-through-member traversal rule.

## Syntax

A definition contains a name, positional parameters, and one or more `EMIT`
statements:

```zc
MACRO name(first, second):
EMIT statement using {{first}} and {{second}}
ENDMACRO.
```

A use site ends with a period:

```zc
USE name(value1, value2).
```

Arguments may contain quoted strings and nested `()`, `[]`, or `{}` values.
Commas inside those nested values remain part of the argument.

## Expansion behavior

`Zil.Parser.Macro.preprocess` performs these steps:

1. collect every macro definition;
2. remove definition blocks from the parser payload;
3. substitute `{{parameter}}` placeholders positionally;
4. recursively expand emitted `USE` statements;
5. return the expanded source lines and an expansion record for each use.

The default expansion limit is 10,000 macro uses, matching the existing
Clojure implementation. Direct and mutual recursion are rejected when a macro
name reappears in the active expansion stack.

## Retained information

A parsed `Zil.Program` stores:

```lean
macros : Array Zil.MacroDef
expansions : Array Zil.MacroExpansion
```

Each expansion records:

- the macro name;
- supplied arguments;
- emitted statements;
- the expansion stack;
- the source line of the `USE` statement.

The expanded semantic program continues to use the existing `TupleExpr`,
`Rule`, and `Query` structures.

## Native APIs

```lean
Zil.Parser.Macro.preprocess
Zil.Parser.Macro.renderExpanded
Zil.Parser.MacroProgram.parseText
Zil.Parser.MacroProgram.parseFile
Zil.Parser.MacroProgram.expandText
```

## CLI

Compile a macro-enabled source file:

```bash
lake exe zil -- compile model.zc Generated.lean Project.Generated
```

Inspect only the expanded source:

```bash
lake exe zil -- expand model.zc
lake exe zil -- expand model.zc expanded.zc
```

## Rejected inputs

The frontend reports an error for:

- duplicate macro names;
- duplicate parameters;
- empty macro bodies;
- unterminated definitions;
- unknown macro uses;
- argument-count mismatches;
- unresolved placeholders;
- recursive expansion cycles;
- expansion-limit exhaustion.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- expand examples/macros/access.zc
```
