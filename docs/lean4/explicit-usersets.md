# Explicit usersets in the native core

Original ZIL tuples may use either a direct subject or a userset subject:

```zc
doc:readme#viewer@group:eng.
doc:readme#viewer@group:eng#member.
```

These statements have different meanings. The first relates the document directly to the group. The second relates the document to all subjects reached through `group:eng#member`.

`Zil.TupleExpr` keeps that distinction:

```lean
private def directGroup : Zil.TupleExpr :=
  Zil.TupleExpr.direct
    (.ground `doc.readme)
    `zil.viewer
    (.ground `group.eng)

private def memberUserset : Zil.TupleExpr :=
  Zil.TupleExpr.withUserset
    (.ground `doc.readme)
    `zil.viewer
    ⟨`group.eng⟩
    `zil.member
```

`TupleExpr.semanticallyEqual` reports these values as different. `Zil.Codec.encodeTuple` and `decodeTuple` preserve the distinction during round trips.

## Lowering into the existing engine

The current Horn engine consumes `RelExpr` facts and `Rule` values. A direct tuple lowers to one fact. A userset tuple lowers to:

1. the stored relation to the userset object;
2. one traversal rule for its outer and inner relations.

For:

```zc
doc:readme#viewer@group:eng#member.
```

the fact is:

```lean
RelExpr.mk'
  (.ground `doc.readme)
  `zil.viewer
  (.ground `group.eng)
```

and the rule has the form:

```lean
object  ⟶[viewer] userset
userset ⟶[member] subject
--------------------------------
object  ⟶[viewer] subject
```

`TupleProgram.lower` combines several tuples and shares rules with the same generated name. This preserves compatibility with the existing query and closure engine while retaining the original tuple form for codecs, source maps, and later Zanzibar-specific processing.

## Canonical tuple encoding

Direct tuple:

```text
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>direct<TAB>node:group.eng
```

Userset tuple:

```text
tuple<TAB>node:doc.readme<TAB>zil.viewer<TAB>userset<TAB>group.eng<TAB>zil.member
```

Source metadata remains outside semantic equality, matching the existing relation and rule codecs.
