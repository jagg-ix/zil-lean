# ZIL tuple-to-Lean translation v0.1

## Purpose

This translation accepts relation facts written with the original ZIL tuple syntax and emits native ZIL Lean declarations.

```text
object#relation@subject [key=value, ...].
```

Example input:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member [source="policy", inherited=true].
doc:readme#parent@folder:A.
```

## Input

A translation unit contains:

```text
[MODULE module-name.]
tuple-fact*
```

`MODULE` is optional. Each tuple fact must end with `.`.

Tuple attributes support strings, integers, decimal literals, booleans, named
terms, and `?variable` terms. Top-level facts must remain ground. Rules, queries,
macros, and higher-level declarations are handled by later parser stages.

## Lossless tuple model

Every source tuple is first represented as `Zil.TupleExpr`.

```lean
inductive TupleSubject where
  | direct : Term → TupleSubject
  | userset : UsersetRef → TupleSubject

structure TupleExpr where
  object : Term
  relation : Name
  subject : TupleSubject
  attrs : Array Attribute
  source : Source
```

This preserves the difference between:

```zc
doc:readme#viewer@group:eng.
doc:readme#viewer@group:eng#member.
```

The first tuple names `group:eng` directly. The second names the subjects reached
through the `member` relation on `group:eng`.

Generated modules expose the source values in:

```lean
def sourceTuples : Array Zil.TupleExpr
```

Each value is registered with:

```lean
zil_register_tuple sourceTuple0
```

Registration lowers the tuple into the `RelExpr` facts and Horn rules used by the
native query engine.

## Attribute semantics

Attributes are finite key/value maps. Keys must be unique. Source order does not
affect semantic equality.

```zc
service:api#depends_on@service:db
  [critical=true, retries=3, ratio=0.75, owner=team:platform].
```

becomes a `TupleExpr` whose `attrs` contain:

```lean
#[
  { key := `critical, value := .boolean true },
  { key := `retries, value := .integer 3 },
  { key := `ratio, value := .decimal "0.75" },
  { key := `owner, value := .term (.ground `team.platform) }
]
```

The lowered `RelExpr` retains the same attribute map. A rule or query pattern may
specify a subset of attributes; every specified key/value pair must match.

## Lean name mapping

Object and subject names use `:`, `/`, and `.` as namespace separators.

```text
doc:readme        → doc.readme
group:eng         → group.eng
user:10           → user.u10
folder:A          → folder.A
lean.Parser.parse → lean.Parser.parse
```

A numeric segment receives a prefix so it forms a valid Lean name. Numeric
segments under `user` use `u`; other numeric segments use `n`.

Relations become canonical names under `zil`:

```text
requires-claim → zil.requiresClaim
requiresClaim  → zil.requiresclaim
supported_by   → zil.supportedBy
```

## Direct facts

A direct tuple:

```zc
doc:readme#owner@user:10.
```

is retained as:

```lean
Zil.TupleExpr.direct
  (.ground `doc.readme)
  `zil.owner
  (.ground `user.u10)
```

and lowers to one `RelExpr` fact.

## Userset subjects

A subject ending in `#relation` names a userset:

```zc
doc:readme#viewer@group:eng#member [source="policy"].
```

It is retained as:

```lean
Zil.TupleExpr.withUserset
  (.ground `doc.readme)
  `zil.viewer
  ⟨`group.eng⟩
  `zil.member
  #[{ key := `source, value := .text "policy" }]
```

Lowering emits the stored relation to `group.eng` and a traversal rule that
follows `member`. The outer premise and derived relation retain the tuple's
attributes.

## Canonical encoding

Direct and userset subjects have separate forms. Attribute data occupies the
final codec column:

```text
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>direct<TAB>node:group.eng<TAB><attrs>
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>userset<TAB>group.eng<TAB>zil.member<TAB><attrs>
```

`Zil.Codec.encodeTuple` and `decodeTuple` preserve direct/userset structure and
attribute values. Older rows without the attribute column remain accepted.

## Native command

```bash
lake exe zil -- compile input.zc output.lean Project.AccessFacts
```

Passing `-` as the output path prints the generated module.

The Clojure compatibility exporter remains available:

```bash
clojure -M:tuple-lean input.zc output.lean Project.AccessFacts
```
