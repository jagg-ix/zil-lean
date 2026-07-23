# ZIL native query governance v1

## Planner hint

```text
as_is
bound_first
high_selectivity_first
```

The first explicit `planner_hint` in source declaration order is used. If no profile declares one, `high_selectivity_first` is used.

## Planning

Only positive query premises are reordered. Negative premises retain source order after all positive premises.

For each positive premise the planner records:

```text
relation cardinality in base facts
number of variables already bound
number of constant endpoints and attributes
original position
```

`high_selectivity_first` compares those fields in the order shown above. `bound_first` compares bound-variable count before cardinality. Higher bound and constant counts are preferred; lower cardinality and source position are preferred.

## Query pack

A `QUERY_PACK` declaration requires `queries` and may define `must_return`.

Names may be bare or prefixed with `query:` / `query.`. Pack references may be bare or prefixed with `query_pack:` / `query_pack.`.

## DSL profile

A `DSL_PROFILE` requires `query_pack` and may define `planner_hint`.

When a requested profile is supplied, absence is an evaluation error. Without a requested profile, every profile is active.

Selected pack names are deduplicated in first-use order. Missing packs are recorded. If no referenced pack resolves, all source query definitions remain selected. Otherwise the selected packs determine the active query set.

Missing query definitions are recorded. `must_return` checks use the selected native query results after checked stratified closure.

## Planner report

```text
ZIL-QUERY-PLAN\t1
module\t<module>
planner-hint\t<hint>
profiles\t<comma-separated names>
cardinality\t<relation>\t<count>
query\t<name>\t<select vars>\t<original relations>\t<planned relations>
```

## Governance report

```text
ZIL-QUERY-CI\t1
status\t<pass|fail>
module\t<module>
planner-hint\t<hint>
requested-profile\t<name or empty>
active-profiles\t<names>
selected-profiles\t<names>
selected-packs\t<names>
selected-queries\t<names>
missing-packs\t<names>
missing-queries\t<names>
facts\t<closed fact count>
must-return\t<query>\t<row count>\t<pass|fail>
query\t<query>\t<row count>
```

## Success

Query governance passes exactly when:

```text
no selected query pack is missing
no selected query definition is missing
every must_return query has at least one row
```

Unsafe, invalid, or non-stratifiable programs are rejected before reporting.
