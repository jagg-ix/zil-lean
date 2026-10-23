# Souffle compatibility macros v1

The `souffle-compat` macros make a compatible subset of Souffle programs explicit and portable
as ZIL source. A Souffle bridge once serialized a compiled ZIL program, invoked Souffle, and
parsed its output; that bridge belonged to the removed Clojure runtime (`spec/clojure-removal.md`).
The macros remain and are qualified on the native Lean frontend.

Supported source constructs:

- binary relations with two `symbol` columns;
- ground binary facts;
- rules with one or two positive binary premises;
- output queries, which map to `.decl` plus `.output` relations.

Use `SOUFFLE_BINARY_RELATION`, `SOUFFLE_BINARY_FACT`,
`SOUFFLE_BINARY_RULE1`, `SOUFFLE_BINARY_RULE2`, and `SOUFFLE_OUTPUT2` from
`libsets/souffle-compat`. For example, `examples/souffle-transitive-closure.zc`
expresses Souffle's recursive transitive-closure pattern.

A ZIL relation is serialized as `(object, subject)`, so the fact and rule macros reverse the
macro-facing arguments when constructing the ZIL atom; a Souffle relation keeps the familiar
`(first, second)` order. Relation macros retain arity and symbol-column metadata in the ZIL model.
They do not map numeric types or Souffle-only features such as aggregates, components, functors,
or disjunction.

Qualification is the macro-extension matrix: native expansion against a reviewed golden, native
ZIL compilation, and generated Lean typechecking.
