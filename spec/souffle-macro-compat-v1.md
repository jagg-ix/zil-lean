# Souffle compatibility macros v1

The ZIL runtime already includes `zil.bridge.souffle`, which serializes a
compiled ZIL program, invokes Souffle, and parses its output. This extension
adds source macros that make the compatible subset explicit and portable
through both the Clojure and native Lean macro frontends.

Supported source constructs:

- binary relations with two `symbol` columns;
- ground binary facts;
- rules with one or two positive binary premises;
- output queries, emitted by the bridge as `.decl` plus `.output` relations.

Use `SOUFFLE_BINARY_RELATION`, `SOUFFLE_BINARY_FACT`,
`SOUFFLE_BINARY_RULE1`, `SOUFFLE_BINARY_RULE2`, and `SOUFFLE_OUTPUT2` from
`libsets/souffle-compat`. For example, `examples/souffle-transitive-closure.zc`
expresses Souffle's recursive transitive-closure pattern.

The bridge serializes a ZIL relation as `(object, subject)`, so the fact and
rule macros reverse the macro-facing arguments when constructing the ZIL atom;
the generated Souffle relation keeps the familiar `(first, second)` order.
Relation macros retain arity and symbol-column metadata in the ZIL model. The
current bridge still emits symbol columns and infers physical declarations
from compiled facts/rules; it does not yet map numeric types or implement
Souffle-only features such as aggregates, components, functors, or disjunction.

Qualification is layered: the macro-extension matrix checks exact Clojure/native
expansion parity, native ZIL compilation, and generated Lean typechecking. The
Clojure Souffle integration test then runs the expanded closure model through
the existing bridge and compares its query rows with the ZIL interpreter.
