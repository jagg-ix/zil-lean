# Native query planning and governance

The native Lean frontend now implements the adaptive planner and `QUERY_PACK` / `DSL_PROFILE` checks previously available only through the Clojure runtime.

## Commands

```bash
bin/zil query-plan examples/query-governance/operations.zc
bin/zil query-ci examples/query-governance/operations.zc operations
```

To evaluate every profile and write a report:

```bash
bin/zil query-ci examples/query-governance/operations.zc - /tmp/query-ci.txt
```

## Planner policies

```text
as_is
bound_first
high_selectivity_first
```

The default is `high_selectivity_first`, matching the legacy runtime.

Positive premises are reordered. Negative premises remain after every positive premise so stratified absence checks retain their execution shape.

### High selectivity first

Candidate order is determined by:

1. lower base-fact relation cardinality;
2. more variables already bound;
3. more constant endpoints or attributes;
4. original source position.

### Bound first

Candidate order is determined by:

1. more variables already bound;
2. lower relation cardinality;
3. more constants;
4. original source position.

## Query packs

```zc
QUERY_PACK operations [
  queries=[services, dependencies],
  must_return=[services]
].
```

A pack selects queries and may require selected queries to return at least one row.

## DSL profiles

```zc
DSL_PROFILE operations [
  query_pack=operations,
  planner_hint=high_selectivity_first
].
```

When a profile name is supplied, it must exist. Referenced packs and queries must exist. Missing references are reported rather than silently ignored.

When no profile selects a valid pack, all source queries remain active, matching the legacy fallback.

## Native API

```lean
Zil.QueryGovernance.PlannerHint
Zil.QueryGovernance.planQuery
Zil.QueryGovernance.planProgram
Zil.QueryGovernance.queryPacks
Zil.QueryGovernance.dslProfiles
Zil.QueryGovernance.checkProgram
Zil.QueryGovernance.renderPlan
Zil.QueryGovernance.renderCi
```

## Reports

The planner emits `ZIL-QUERY-PLAN/1` with module, planner hint, active profiles, relation cardinalities, and original/planned relation order per query.

The governance command emits `ZIL-QUERY-CI/1` with profile and pack selection, missing references, query row counts, `must_return` checks, final closure size, and an overall pass/fail status.

## Exit status

```text
query-plan
  0 report generated
  1 parse or planner failure
  2 invalid command form

query-ci
  0 all governance checks passed
  1 missing references, failed must_return, or evaluation failure
  2 invalid command form
```

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil query-plan examples/query-governance/operations.zc
bin/zil query-ci examples/query-governance/operations.zc operations
```
