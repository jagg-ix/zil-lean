# Native `.zc` tuple parser

The native Lean frontend parses the original ZIL tuple syntax directly:

```zc
MODULE policy.access.

doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

## API

```lean
Zil.Parser.parseText
Zil.Parser.parseFile
Zil.Parser.renderLeanModule
Zil.Parser.defaultNamespace
```

`parseText` returns `Zil.TupleProgram`. Every tuple records its original line number through `Source.line`.

The parser accepts:

- one optional `MODULE` declaration;
- ground direct tuple facts;
- userset subjects of the form `object#relation`;
- blank lines;
- full-line `//` comments.

The tuple-only stage reports structured errors for:

- missing final periods;
- duplicate `MODULE` declarations;
- missing or repeated separators;
- empty terms;
- nested selectors beyond one userset relation;
- tuple attributes.

Attributes, source rules, queries, and higher-level declarations remain separate later frontend targets.

## Command

Print generated Lean source:

```bash
lake exe zil -- compile examples/tuple-lean/access.zc
```

Write the source to a file:

```bash
lake exe zil -- compile \
  examples/tuple-lean/access.zc \
  Generated/Access.lean
```

Select the output namespace:

```bash
lake exe zil -- compile \
  examples/tuple-lean/access.zc \
  Generated/Access.lean \
  Project.AccessFacts
```

The generated module contains:

1. lossless `sourceTuples : Array Zil.TupleExpr` values;
2. compatible `zil_fact` declarations;
3. generated traversal rules for userset subjects.

## Name conversion

```text
doc:readme        → doc.readme
group:eng         → group.eng
user:10           → user.u10
requires-claim    → zil.requiresClaim
supported_by      → zil.supportedBy
```

Numeric segments receive a prefix that forms a valid Lean name. Numeric segments under `user` receive `u`; other numeric segments receive `n`.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- compile examples/tuple-lean/access.zc -
lake env lean examples/tuple-lean/Access.lean
```
