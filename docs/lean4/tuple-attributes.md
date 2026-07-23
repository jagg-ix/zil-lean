# Tuple attributes

ZIL tuple facts may carry a finite key/value map:

```zc
service:api#depends_on@service:db
  [critical=true, retries=3, ratio=0.75, owner=team:platform, note="primary"].
```

The native parser stores these entries on both `Zil.TupleExpr` and its lowered
`Zil.RelExpr`.

## Value types

The native core supports:

```lean
Zil.AttrValue.text
Zil.AttrValue.integer
Zil.AttrValue.decimal
Zil.AttrValue.boolean
Zil.AttrValue.term
```

A term value may be a named node or a `?variable` when used by a rule or query.
Top-level tuple facts must remain ground.

## Equality and matching

Attribute order does not affect semantic equality. Keys must be unique within a
tuple.

A query or rule relation may provide a subset of attributes. Each provided entry
must exist on the matching fact and have the same value. Term-valued attributes
use the same variable binding rules as relation endpoints.

## Generated Lean

The compiler emits a lossless tuple value and registers its lowering:

```lean
private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `service.api)
      `zil.dependsOn
      (.ground `service.db) with
    attrs := #[
      { key := `critical, value := .boolean true },
      { key := `retries, value := .integer 3 }
    ]
    source := { frontend := "zc", line := some 2 } }

zil_register_tuple sourceTuple0
```

`zil_register_tuple` adds the lowered fact and any userset traversal rule to the
persistent Lean environment.

## Codec compatibility

Canonical relation and tuple codecs include attributes. Older attribute-free
rows remain accepted and decode with an empty attribute map.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- compile examples/tuple-lean/access.zc -
```
