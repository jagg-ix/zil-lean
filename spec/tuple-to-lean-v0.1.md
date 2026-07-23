# ZIL tuple-to-Lean translation v0.1

## Purpose

This translation accepts relation facts written with the original ZIL tuple syntax and emits native ZIL Lean declarations.

```text
object#relation@subject.
```

Example input:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

## Input

A translation unit contains:

```text
[MODULE module-name.]
tuple-fact*
```

`MODULE` is optional. Each tuple fact must end with `.`.

The v0.1 translator accepts facts without attributes. Rules, queries, standard-library declarations, and attributes produce an error with the unsupported construct reported.

## Lossless tuple model

Every source tuple is first represented as `Zil.TupleExpr`.

```lean
inductive TupleSubject where
  | direct : Term → TupleSubject
  | userset : UsersetRef → TupleSubject
```

This preserves the difference between:

```zc
doc:readme#viewer@group:eng.
doc:readme#viewer@group:eng#member.
```

The first tuple names `group:eng` directly. The second names the subjects reached through the `member` relation on `group:eng`.

Generated modules expose the source values in:

```lean
def sourceTuples : Array Zil.TupleExpr
```

The source values are then lowered into the existing `RelExpr` facts and Horn rules used by the native query engine.

## Lean name mapping

Object and subject names use `:`, `/`, and `.` as namespace separators.

```text
doc:readme        → doc.readme
group:eng         → group.eng
user:10           → user.u10
folder:A          → folder.A
lean.Parser.parse → lean.Parser.parse
```

A numeric segment receives a prefix so it forms a valid Lean name. Numeric segments under `user` use `u`; other numeric segments use `n`.

Relations become Lean identifiers. Separator-delimited and camel-case source names map to lower camel case:

```text
requires-claim → requiresClaim
requiresClaim  → requiresClaim
supported_by   → supportedBy
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

and lowers to:

```lean
zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)
```

## Userset subjects

A subject ending in `#relation` names a userset:

```zc
doc:readme#viewer@group:eng#member.
```

It is retained as:

```lean
Zil.TupleExpr.withUserset
  (.ground `doc.readme)
  `zil.viewer
  ⟨`group.eng⟩
  `zil.member
```

The lowering emits the stored relation to the userset object:

```lean
zil_fact
  node(doc.readme)
    ⟶[viewer]
  node(group.eng)
```

It also emits one rule for each distinct outer/inner relation pair:

```lean
zil_theorem_rule viewerViaMember
  {object userset subject : Zil.Node}
  (hOuter : object ⟶[viewer] userset)
  (hInner : userset ⟶[member] subject)
  : object ⟶[viewer] subject
```

The lossless tuple remains available even after lowering, so codecs and later Zanzibar-specific processing can distinguish a direct group relation from a userset relation.

Repeated userset patterns share one generated rule.

## Canonical encoding

Direct and userset subjects have separate forms:

```text
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>direct<TAB>node:group.eng
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>userset<TAB>group.eng<TAB>zil.member
```

`Zil.Codec.encodeTuple` and `decodeTuple` preserve this distinction. Source metadata is excluded from semantic equality.

## Namespace

The output namespace may be supplied explicitly. Otherwise it is derived from the `MODULE` declaration or the input filename under `Zil.Generated`.

```text
access.zc              → Zil.Generated.Access
MODULE policy.access.  → Zil.Generated.Policy.Access
```

## Command

```bash
clojure -M:tuple-lean input.zc output.lean Project.AccessFacts
```

Passing `-` as the output path prints the Lean module to standard output.

```bash
clojure -M:tuple-lean input.zc -
```

The convenience script provides the same translation:

```bash
bash ./bin/zil-tuples-lean input.zc output.lean Project.AccessFacts
```
