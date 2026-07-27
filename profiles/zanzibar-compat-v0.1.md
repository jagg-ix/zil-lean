# Zanzibar Compatibility Profile v0.1 (Draft)

This profile layers authorization-specific semantics on top of Zil.

## Primitives

- `this`
- `computed_userset(relation)`
- `tuple_to_userset(tupleset_relation, computed_relation)`

## Composition

- union (`+`)
- intersection (`&`)
- exclusion (`-`)

## Notes

- Profile semantics are separate from general Zil semantics.
- Profile evaluation must be stratified and deterministic.

