# Model substrate: targets and tests (living checklist)

Contract: `spec/model-substrate-v0.1.md`. Rule for every target: write the failing tests, see them
fail for the stated reason, implement, see them pass, then start the next target. The compatibility
gate (below) is green at every step.

Tests lent in `Zil/Test/ModelSubstrate.lean`. They read the real library files from
`libsets/model-substrate/`, so a test exercises the shipped text, not a copy.

## Compatibility gate (every target)

- `lake build zilLeanTests` passes, including the existing `Zil.Test.Macro`, `MacroLibrary`,
  `DatalogMacro` and `Declarations`.
- `bin/zil macro-parity examples/macro-extension/model.zc` reports `:exact true`.
- `scripts/check-model-substrate-names.sh`: no existing library defines a `MODEL_*` or `SCENARIO_*`
  macro, and none uses a `model_` or `scenario_` relation.

## Targets

| ID | Target | Done when | Status |
|---|---|---|---|
| T0 | Spec freeze | Names, arities, tuple shapes, ID rules and non-goals written; this inventory accepted; stub library files exist | done |
| T1 | Structure core | Entity, attribute, operation, association, generalisation expand; ends queryable after closure | done |
| T2 | Structure behaviour | State, transition, message, ordering expand; reachable operations queryable | done |
| T3 | Intent surface | Actor, use case, participation, include, extend expand | done |
| T4 | Scenario core | Feature, case, given/when/then with ordinals, tags expand; steps of a scenario queryable | done |
| T5 | Coverage bridges | `MODEL_COVERED_BY`, `SCENARIO_REALIZES`; uncovered and orphan queries | done |
| T6 | Composition | Ordered load; a domain stub `EMIT USE`s the substrate; nesting and cycles | done |
| T7 | Compatibility and parity | Old macros unchanged; Lean and Clojure expansions equal | done |
| T8 | Ingest alignment (optional) | A scenario step key can be matched to a Cucumber report step name | not started |

T0 to T7 are the shippable spine and are done. T8 is thin and optional; it is not started because it
needs a step-name slug convention that the substrate does not define, and the Cucumber adapter is
unchanged either way.

`scripts/test-model-substrate.sh` runs the whole gate: the Lean tests (including every existing macro
suite), the prefix check, the example golden and row counts, and Lean/Clojure expansion parity for the
legacy example, the worked example and the composition fixture.

## Test inventory

Names are the Lean test names in `Zil/Test/ModelSubstrate.lean`.

### T1 structure core

| Test | Asserts |
|---|---|
| `expand_entity` | `USE MODEL_ENTITY(book)` yields exactly `book#model_kind@entity:model_entity.` |
| `expand_attr_op` | attribute and operation facts, owner links |
| `expand_assoc` | `MODEL_ASSOC(a, book, loan, one, many)` yields kind, source, target and both multiplicities |
| `expand_generalize` | child to parent edge |
| `query_assoc_ends` | after `MODEL_RULES` and closure, `FIND ?e WHERE a#model_end@?e` returns both ends |
| `query_is_a_star` | a three-level chain is shelved transitively |
| `unknown_macro_fails` | `USE MODEL_NOPE(x)` is an expansion error |
| `arity_fails` | `USE MODEL_ENTITY(a, b)` is an expansion error |

### T2 structure behaviour

| Test | Asserts |
|---|---|
| `expand_state_trans` | state, initial, and from/event/to edges of a transition |
| `expand_msg` | from/to/calls edges; `MODEL_MSG_AFTER` order edge |
| `query_can_call` | an operation is reachable from the entity that sends the message |

### T3 intent surface

| Test | Asserts |
|---|---|
| `expand_actor_uc` | actor, use case, participation |
| `expand_include_extend` | edges only, in the stated direction |

### T4 scenario core

| Test | Asserts |
|---|---|
| `expand_feature_case` | feature owns the case |
| `expand_gwt_order` | given, when, then carry keyword, ordinal and key |
| `query_steps_for_scenario` | `FIND ?st` returns every step of one scenario and none of another |
| `tag_facts` | `SCENARIO_TAG` on a feature, a case and a use case |

### T5 coverage bridges

| Test | Asserts |
|---|---|
| `covered_by` | use case to scenario link |
| `step_realizes` | step to target link |
| `coherence_uncovered` | a use case with no scenario is in `p_uncovered_usecases`, a covered one is not |
| `coherence_orphan` | a case with no link is in `p_orphan_scenarios`; one covered, or one with a realizing step, is not |
| `coherence_unrealized_then` | a `then` step that realizes nothing is listed; one that does is not |
| `coherence_two_instances` | two prefixes in one model do not collide |

### T6 composition

| Test | Asserts |
|---|---|
| `lib_order` | all library files plus a model that uses two of them expand and parse |
| `domain_emits_substrate` | a domain stub macro `EMIT USE`s `MODEL_ENTITY` and `MODEL_STATE` and expands |
| `nested_emit_use` | substrate macros nested three deep expand within the depth limit; a cyclic domain stub is rejected |
| `module_header_dropped` | each library's own `MODULE` header is dropped from the composed unit |

### T7 compatibility and parity

| Test / check | Asserts |
|---|---|
| `legacy_macro_suite` | the existing macro tests still pass (`lake build zilLeanTests`) |
| `no_lib_noop` | a model expanded with an empty library list equals its golden expansion |
| `name_no_shadow` | the expansion of a TLM-only snippet is byte-equal with and without the substrate loaded |
| `names_disjoint` | `scripts/check-model-substrate-names.sh` |
| `frontend_parity` | `bin/zil macro-parity` reports `:exact true` for each fixture and example with `--lib libsets/model-substrate` |
| `legacy_example_parity` | `bin/zil macro-parity examples/macro-extension/model.zc` is exact |

### T8 ingest alignment (optional)

| Test | Asserts |
|---|---|
| `step_key_aligns` | the key of a scenario step equals the slug of a step name in a fixture Cucumber JSON report; the adapter is unchanged |

## Fixtures and examples

```text
libsets/model-substrate/        shipped library (00, 05, 10, 20, 30)
examples/model-substrate/       a neutral worked example and its expanded golden
test/fixtures/model-substrate/  T6 and T7 inputs
scripts/check-model-substrate-names.sh
scripts/test-model-substrate.sh   gate: Lean tests, golden diff, parity, name check
```
