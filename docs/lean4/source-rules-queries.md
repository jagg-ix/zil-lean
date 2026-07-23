# Source rules and queries

The native Lean frontend parses tuple facts, Horn rules, and conjunctive queries
from one `.zc` source unit.

```zc
MODULE policy.access.

doc:readme#viewer@group:eng [source=manual].
group:eng#member@user:11.

RULE groupViewer:
IF ?document#viewer@?group [source=manual] AND ?group#member@?user
THEN ?document#viewer@?user [source=manual].

QUERY viewers:
FIND ?user WHERE doc:readme#viewer@?user [source=manual].
```

## Program model

```lean
structure Zil.Program where
  moduleName : Option Name
  tuples : Array Zil.TupleExpr
  rules : Array Zil.Rule
  queries : Array Zil.Query
```

`Program.facts` lowers stored tuples. `Program.allRules` combines source rules
with userset traversal rules.

## Rule normalization

The source language permits several atoms in a `THEN` clause:

```zc
THEN ?doc#viewer@?user AND ?doc#auditable@?user.
```

The native core keeps single-head Horn rules. The parser therefore emits:

```text
groupViewer.head_0
groupViewer.head_1
```

Both rules retain the same body, variable order, source location, and graph trust
classification.

## Variable safety

Rule variables are inferred from the `IF` body. Every variable used by `THEN`
must already occur in the body.

```zc
RULE unsafe:
IF ?doc#viewer@?group
THEN ?doc#viewer@?unbound.
```

The parser rejects this rule at the `THEN` source line.

## Queries

A query stores:

- its stable name;
- variables found in `WHERE`;
- selected variables from `FIND`;
- conjunctive relation patterns;
- its source line.

Every selected variable must occur in `WHERE`.

```lean
let closed := Zil.Engine.closure program.facts program.allRules
let answers := Zil.Engine.solve closed program.queries[0]!
```

## Attributes

Rule and query atoms use the same attribute values and subset-matching semantics
as tuple facts. Term-valued attribute variables participate in the existing
binding map.

## Generated Lean

`lake exe zil -- compile` emits:

- lossless `sourceTupleN` values;
- normalized `sourceRuleN` values;
- `sourceQueryN` values;
- tuple and rule registration commands;
- one `sourceProgram : Zil.Program` value.

```bash
lake exe zil -- compile model.zc Generated/Model.lean Project.Model
```

## Current rule fragment

This stage implements positive Horn bodies. `NOT` and stratification are handled
by the next language-core target.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- compile model.zc -
```
