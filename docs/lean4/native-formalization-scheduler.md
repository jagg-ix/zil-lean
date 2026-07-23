# Native formalization scheduling

`FORMALIZATION_TARGET` declarations can now be planned by the native Lean frontend.

## Commands

```bash
bin/zil formalization-plan examples/formalization/native-plan.zc
bin/zil formalization-next examples/formalization/native-plan.zc
```

The complete plan includes every target, its lifecycle state, priority, readiness, dependencies, blocking reasons, module, file, and declaration.

The next-target command returns the highest-priority ready target.

## Scheduling rules

A target is selectable when its status is:

```text
ready
in_progress
```

A dependency is satisfied only when its status is:

```text
verified
reviewed
proved
```

`implemented` does not satisfy a dependency because implementation and verification remain separate states.

Targets are ordered by:

1. priority descending;
2. target identifier ascending for equal priorities.

## Validation

The scheduler rejects:

- duplicate target identifiers;
- dependencies that name no target;
- direct or transitive dependency cycles;
- missing module, file, declaration, status, or priority fields;
- negative or non-integer priorities;
- unsupported lifecycle states.

## Report format

```text
ZIL-FORMALIZATION-PLAN  1
target  finiteModel  ready  80  ready  foundations  ...
target  continuumLimit  ready  60  blocked  finiteModel  dependency:finiteModel:ready  ...
```

The report is tab-separated and deterministic.

## Native API

```lean
Zil.Formalization.Target.ofDeclaration
Zil.Formalization.validate
Zil.Formalization.plan
Zil.Formalization.next?
Zil.Formalization.fromProgram
Zil.Formalization.renderPlan
Zil.Formalization.renderNext
```

## Validation commands

```bash
lake build
lake exe zilLeanTests
bin/zil formalization-plan examples/formalization/native-plan.zc
```
