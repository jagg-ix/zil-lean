# ZIL model substrate v0.1

An opt-in macro library that gives every domain macro system one shared vocabulary for **structure**
(things, links, states, messages), **intent** (actors and use cases), **behaviour** (feature and
scenario steps) and the **coverage links** between them. It is written in the ordinary `.zc` macro
language (`spec/native-macro-v0.1.md`). It adds no relation kind, statement form, parser rule or
Lean definition to ZIL.

The vocabulary has the shape of a class/use-case/state/sequence model and of a Given/When/Then
feature file, but it is not UML and not Gherkin. No diagram tool, XMI file or `.feature` file is the
authority; the facts are.

## Layering

```text
core tuples / rules / queries
        ^
shared model substrate (this document)        libsets/model-substrate/
        ^
domain macros (TLM_*, PN_*, THM_*, AWS_*, ...) may `EMIT USE` the substrate
```

A domain library that wants shared structure writes `EMIT USE MODEL_ENTITY({{name}})` in its own
macro. A domain that does not is untouched. The substrate never calls a domain macro.

## Compatibility contract

1. **Opt in.** A model that does not load `libsets/model-substrate` expands, parses and compiles
   exactly as before. A library directory is selected with `--lib DIR`; it is never discovered.
2. **No shadowing.** Every public macro starts with `MODEL_` or `SCENARIO_`; every relation the
   substrate emits starts with `model_` or `scenario_`. No existing library defines either prefix
   (checked by `scripts/check-model-substrate-names.sh`). Loading the substrate does not change the
   expansion of any existing macro.
3. **Only existing statement forms.** Macros emit tuples, `RULE`, `QUERY` and nested `USE`. Nothing
   is added to the kernel.
4. **Stable names.** A released macro never changes its arity or the tuples it emits. A breaking
   change adds a new macro name.
5. **Golden expansion.** The worked example expands to a reviewed golden
   (`bin/zil expand MODEL OUT --lib libsets/model-substrate`, checked by `scripts/test-model-substrate.sh`).

## Identifier rules

- Arguments are **opaque IDs**, written by the caller and substituted verbatim. A macro never adds a
  prefix to an ID. A domain can therefore pass `tlm:component:cpu0` to `MODEL_ENTITY` and refer to the
  same subject from its own facts.
- IDs follow the tuple name rules: `-` becomes `_`, `:` and `/` become namespace separators, a
  segment that begins with a digit gains a letter prefix, and an empty segment (`a..b`) is rejected.
- Tokens that the macro places after `value:` (`event`, `ordinal`, `key`, `title`, `mult`) must be
  single names. Free text does not fit in a tuple (commas and brackets break the attribute parser),
  so a step carries a **key**, an opaque token the caller derives from its own wording, never the
  wording itself.
- Multiplicity tokens: `one`, `optional`, `many`, `some` (exactly one, zero or one, any number, one or
  more). Not enforced; a model may use other single-name tokens.
- Ordinals are bare positive integers (`1`, `2`, ...). `value:1` is read as `value.n1`.

## Relation notation

Facts are written `A#rel@B`, read "A rel B". (In ZIL's own terms the left side is the tuple's
object and the right side its subject; the substrate only ever reads them as "A rel B".)
A relation name is normalised by the tuple parser, so `model_kind` is `zil.modelKind`.

## Structure macros (`00-model-structure.zc`)

| Macro | Arguments | Emits |
|---|---|---|
| `MODEL_ENTITY` | `id` | `id#model_kind@entity:model_entity` |
| `MODEL_ATTR` | `attr, owner, type` | `attr#model_kind@entity:model_attr`, `owner#model_has_attr@attr`, `attr#model_type@type` |
| `MODEL_OP` | `op, owner` | `op#model_kind@entity:model_op`, `owner#model_has_op@op` |
| `MODEL_ASSOC` | `assoc, source, target, source_mult, target_mult` | `assoc#model_kind@entity:model_assoc`, `assoc#model_source@source`, `assoc#model_target@target`, `assoc#model_source_mult@value:source_mult`, `assoc#model_target_mult@value:target_mult` |
| `MODEL_GENERALIZE` | `child, parent` | `child#model_is_a@parent` |
| `MODEL_STATE` | `state, owner` | `state#model_kind@entity:model_state`, `owner#model_has_state@state` |
| `MODEL_INITIAL` | `state` | `state#model_initial@value:true` |
| `MODEL_TRANS` | `trans, from, event, to` | `trans#model_kind@entity:model_transition`, `trans#model_from@from`, `trans#model_event@value:event`, `trans#model_to@to` |
| `MODEL_MSG` | `msg, from, to, op` | `msg#model_kind@entity:model_message`, `msg#model_from@from`, `msg#model_to@to`, `msg#model_calls@op` |
| `MODEL_MSG_AFTER` | `later, earlier` | `later#model_after@earlier` |

## Intent macros (`05-model-intent.zc`)

| Macro | Arguments | Emits |
|---|---|---|
| `MODEL_ACTOR` | `actor` | `actor#model_kind@entity:model_actor` |
| `MODEL_USECASE` | `uc` | `uc#model_kind@entity:model_usecase` |
| `MODEL_PARTICIPATES` | `actor, uc` | `actor#model_participates@uc` |
| `MODEL_INCLUDE` | `base, included` | `base#model_includes@included` |
| `MODEL_EXTEND` | `extension, base` | `extension#model_extends@base` |

`include` and `extend` are edges only. They carry no tool semantics.

## Scenario macros (`10-scenario.zc`)

| Macro | Arguments | Emits |
|---|---|---|
| `SCENARIO_FEATURE` | `feature, title` | `feature#scenario_kind@entity:scenario_feature`, `feature#scenario_title@value:title` |
| `SCENARIO_CASE` | `scenario, feature` | `scenario#scenario_kind@entity:scenario_case`, `feature#scenario_has_case@scenario` |
| `SCENARIO_STEP` | `step, scenario, keyword, ordinal, key` | `step#scenario_kind@entity:scenario_step`, `step#scenario_keyword@value:keyword`, `step#scenario_ordinal@value:ordinal`, `step#scenario_key@value:key`, `scenario#scenario_has_step@step` |
| `SCENARIO_GIVEN` | `step, scenario, ordinal, key` | `SCENARIO_STEP` with keyword `given` |
| `SCENARIO_WHEN` | `step, scenario, ordinal, key` | `SCENARIO_STEP` with keyword `when` |
| `SCENARIO_THEN` | `step, scenario, ordinal, key` | `SCENARIO_STEP` with keyword `then` |
| `SCENARIO_TAG` | `entity, tag` | `entity#scenario_tag@tag:tag` |

Order is the **ordinal** of a step within its scenario, locked as an explicit fact so no query
depends on source line order. `And` and `But` are written as another step of the same keyword.
Not in v0.1: backgrounds, outlines, example tables.

## Bridge macros (`20-model-bridges.zc`)

| Macro | Arguments | Emits |
|---|---|---|
| `MODEL_COVERED_BY` | `uc, scenario` | `uc#model_covered_by@scenario` |
| `SCENARIO_REALIZES` | `step, target` | `step#scenario_realizes@target` |

`target` is any ID: an operation, a transition, a message, an entity, or a domain ID.

## Derived facts and queries (`30-model-coherence.zc`)

Each macro takes a **prefix** `p`. Rule and query names are `p_...`, so a model may hold several
instances under different prefixes. Use one prefix per use: the engine does not reject a repeated
prefix, but it repeats the rules and lists each query twice in a report.

`MODEL_RULES(p)` derives:

| Derived fact | From |
|---|---|
| `a#model_end@e` for both ends of an association | `model_source`, `model_target` |
| `c#model_is_a_star@a` (transitive generalisation) | `model_is_a` |
| `e#model_can_call@op` | a message `from` e that `calls` op |
| `uc#model_has_coverage@value:true` | `model_covered_by` |
| `s#model_has_link@value:true` for a scenario | being covered by a use case, or having a step that realizes something |
| `st#scenario_has_realization@value:true` | `scenario_realizes` |

`MODEL_COHERENCE(p)` uses `MODEL_RULES(p)` and adds three queries that list **violations**:

| Query | Rows |
|---|---|
| `p_uncovered_usecases` | use cases with no covering scenario |
| `p_orphan_scenarios` | scenarios with no use case and no realized target |
| `p_unrealized_then_steps` | `then` steps that realize nothing |

A `QUERY_PACK` that lists these as violation queries expects zero rows.

## Composition

Library files load in filename order before the model. Macro definitions are collected before any
expansion, so a domain library may call a substrate macro whatever the order. Because `--lib`
selects one directory, a model that combines the substrate with a domain library puts both sets of
files in one directory (copies or symlinks); the substrate files keep their `00`, `05`, `10`, `20`,
`30` prefixes, a domain library uses `50` or higher.

## Non-goals

- UML or Gherkin conformance, import or export. (An authoring front end from `.feature` files is
  possible later and is a separate tool.)
- Any change to the kernel, the parser, the macro language or the Cucumber JSON adapter.
- Replacing TLC, the Lean checks, Horn resolution or Datalog.
- Mandatory use by TLM, Petri-net, theorem or AWS macros.

## Targets and tests

See `spec/model-substrate-targets-v0.md`.
