# ZIL native formalization plan v1

## Source

The scheduler consumes `FORMALIZATION_TARGET` declarations from one native parsed `Zil.Program`.

Required fields:

```text
module
file
declaration
status
priority
```

Optional field:

```text
dependencies
```

## Lifecycle

Selectable states:

```text
ready
in_progress
```

Dependency-accepted states:

```text
verified
reviewed
proved
```

Other states are retained in the plan but are not ready.

## Validation

The target set must have:

- unique target IDs;
- nonnegative integer priorities;
- existing dependency targets;
- an acyclic dependency graph.

## Readiness

A target is ready exactly when:

```text
status is selectable
and every dependency status is accepted
```

Blocking reasons use:

```text
status:<status>
missing:<target>
dependency:<target>:<status>
```

Missing dependencies are rejected during set validation, so `missing` reasons are retained only for defensive API use.

## Ordering

Decisions are sorted by priority descending, then identifier ascending.

## Plan report

```text
ZIL-FORMALIZATION-PLAN\t1
target\t<id>\t<status>\t<priority>\t<ready|blocked>\t<dependencies>\t<reasons>\t<module>\t<file>\t<declaration>
```

## Next report

When a target is ready:

```text
ZIL-FORMALIZATION-NEXT\t1\t<id>\t<module>\t<file>\t<declaration>\t<priority>\t<dependencies>
```

When none is ready:

```text
ZIL-FORMALIZATION-NEXT\t1
none
```
