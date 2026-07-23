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

emits:

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

The translator emits the relation to the userset object:

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

This rule preserves the meaning of `group:eng#member`: every subject connected to `group.eng` by `member` receives the outer `viewer` relation.

Repeated userset patterns share one generated rule.

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
