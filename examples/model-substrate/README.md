# Model substrate example

`book-loan/model.zc` models one small flow twice, with the shared macros in
`libsets/model-substrate`, and links the two models:

- structure: a book and its loans, two operations, two states and one transition, one message;
- intent: a reader and two use cases;
- scenarios: one feature with one case of four steps (given, when, then, then);
- links: the case covers one use case; two steps realize an operation and a transition.

The example leaves two gaps on purpose, so the coherence queries have something to report:

| Query | Expected rows | Why |
|---|---|---|
| `c_uncovered_usecases` | `return_book` | no scenario covers it |
| `c_orphan_scenarios` | none | the case covers a use case |
| `c_unrealized_then_steps` | `t2` | the second `then` step realizes nothing |

```bash
bin/zil expand examples/model-substrate/book-loan/model.zc /tmp/book-loan.expanded.zc \
  --lib libsets/model-substrate
bin/zil query-ci examples/model-substrate/book-loan/model.zc loan_profile /tmp/report.tsv \
  --lib libsets/model-substrate
```

`expected.expanded.zc` is the golden expansion and `expected.query-counts.tsv` the expected row
count of each query. `scripts/test-model-substrate.sh` compares both.

In a real model the three `c_*` queries are violation queries: put them in a query pack without
`must_return`, and zero rows is the healthy answer.

## Using the substrate from a domain library

A domain macro calls the substrate with `EMIT USE` and passes its own IDs, so both vocabularies
describe the same subjects:

```text
MACRO DEMO_COMPONENT(name, role):
EMIT demo:component:{{name}}#demo_role@value:{{role}}.
EMIT USE MODEL_ENTITY(demo:component:{{name}}).
ENDMACRO.
```

`--lib` selects one directory, so put the substrate files and the domain library in one directory
(copies or symlinks; substrate files keep their `00` to `30` prefixes, a domain library uses `50` or
higher). `test/fixtures/model-substrate/t6_compose/` is a worked case.
