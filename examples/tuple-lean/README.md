# Original ZIL tuples to native ZIL Lean

Write relation facts with the original ZIL tuple syntax:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

Generate a Lean module:

```bash
clojure -M:tuple-lean \
  examples/tuple-lean/access.zc \
  examples/tuple-lean/Access.lean \
  Zil.Generated.Access
```

The convenience script calls the same exporter:

```bash
bash ./bin/zil-tuples-lean \
  examples/tuple-lean/access.zc \
  examples/tuple-lean/Access.lean \
  Zil.Generated.Access
```

Omit the output path, or pass `-`, to print the generated Lean source:

```bash
clojure -M:tuple-lean examples/tuple-lean/access.zc -
```

## Generated names

Tuple names are converted into Lean names by replacing tuple namespace separators with dots:

```text
doc:readme       → doc.readme
group:eng        → group.eng
user:10          → user.u10
folder:A         → folder.A
```

The `u` prefix makes numeric user identifiers valid Lean name segments. Existing dotted Lean names keep their spelling:

```text
lean.Parser.parse → lean.Parser.parse
```

## Usersets

This tuple contains a userset subject:

```zc
doc:readme#viewer@group:eng#member.
```

The exporter emits the base fact:

```lean
zil_fact
  node(doc.readme)
    ⟶[viewer]
  node(group.eng)
```

It also emits a rule that follows the userset's `member` relation:

```lean
zil_theorem_rule viewerViaMember
  {object userset subject : Zil.Node}
  (hOuter : object ⟶[viewer] userset)
  (hInner : userset ⟶[member] subject)
  : object ⟶[viewer] subject
```

Together with:

```lean
zil_fact
  node(group.eng)
    ⟶[member]
  node(user.u11)
```

rule evaluation can add:

```text
doc.readme ── viewer ──▶ user.u11
```

## Current input scope

The exporter accepts an optional `MODULE` declaration followed by tuple facts. It reports rules, queries, standard-library declarations, and tuple attributes as unsupported so their meaning is preserved for later dedicated translations rather than being dropped.
