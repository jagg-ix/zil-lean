# Lean-native acceptance specification v0.1

This specification defines measurable behavior for the first implementation series.

## A. Canonical relational IR

Legacy `.zc`, embedded comment annotations, and Lean-native syntax must normalize to one equivalent representation containing:

- subject term;
- canonical relation name;
- object term;
- bound variables;
- source location;
- origin and trust class;
- profile version.

### Validation

- Round-trip parse, normalize, emit, and parse preserves semantic equality.
- Alias normalization cannot create duplicate canonical relations.
- Unbound variables are rejected.

## B. Native rule syntax

The preferred Lean frontend is theorem-shaped:

```lean
zil_rule transferRequirement
    {claim requirement declaration : Zil.Node}
    (hFormalizes : declaration ⟶[formalizes] claim)
    (hRequires : declaration ⟶[requires] requirement) :
    claim ⟶[requiresClaim] requirement
```

### Validation

- No Datalog `?var`, postfix `IF`, textual `AND`, `#`, or `@` is needed in native Lean files.
- Legacy and native forms produce equal canonical rules.
- Invalid endpoint kinds produce source-located diagnostics.

## C. Query behavior

Native query, check, and expand operations must report:

- result bindings or Boolean result;
- knowledge revision;
- profile version;
- completeness;
- derivation and trust class when applicable.

## D. Trust separation

- Declarative graph rules may derive graph facts.
- Only kernel-certified Lean rules may produce proof terms or discharge Lean goals.
- A graph-derived fact cannot acquire `kernel_checked` trust through an ordinary rule.

## E. Formalization contracts

A file contract declares advertised scope, required formal objects, forbidden substitutions, abstraction level, and completion status.

### Blocking conditions

- A file promises a domain formalization but only contains unrelated or strictly weaker algebraic facts.
- Documentation claims exceed the linked theorem statement.
- Scope is weakened without an explicit contract revision.
- A completed status is asserted while critical required objects are absent.

## F. Agent recovery

A mutating formalization action must be rejected when:

- its context revision is stale;
- the file contract changed after context acquisition;
- a critical theorem-intent mismatch is unresolved;
- no rollback checkpoint exists for the action.

## Required test classes

Every feature PR must include:

1. positive tests;
2. negative tests;
3. semantic round-trip tests;
4. Clojure/Lean cross-boundary parity tests when both implementations apply.
