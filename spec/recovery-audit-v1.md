# ZIL recovery audit v1

## Scope

This specification defines the native terminal audit over one action-token request, its checkpointed single-use execution, required postcondition observations, and an optional precommitted recovery event.

## Inputs

The audit consumes one parsed `Zil.Program` and one request node.

The request node MUST resolve through `Zil.ActionToken.fromProgram` and `Zil.TokenLifecycle.auditProgram`.

The lifecycle MUST reach `consumed` before postcondition verification or recovery can establish a safe terminal state.

## Postcondition events

A postcondition event has relation `zil.postconditionEvent`, the audited request as subject, and a ground object whose `post.` prefix is removed to obtain the postcondition name.

Required attributes:

- `passed`: Boolean.

Optional attributes:

- `evidence`: ground text. It is mandatory and nonempty whenever `passed=true`.

The required name set is copied from the issued token's `action.requiredPostconditions` array.

For every required name:

1. zero observations produce `missing`;
2. one failed observation produces `failed`;
3. one passing observation with empty evidence produces `evidence-missing`;
4. more than one observation produces `duplicates`.

Duplicate names are emitted once in lexical order.

## Recovery event

A recovery event has relation `zil.recoveryEvent` and the audited request as subject.

Required attributes:

- `kind`;
- `reference`;
- `completed`.

Optional attributes:

- `evidence`, which MUST be nonempty for a valid recovery.

A valid recovery MUST satisfy all of the following:

1. verification did not pass;
2. `kind` exactly equals the issued token rollback kind;
3. `reference` exactly equals the issued token rollback reference;
4. `completed=true`;
5. evidence is nonempty.

A recovery event supplied after direct verification is an `unexpected-recovery` failure.

## Outcomes

Outcome ordering is deterministic.

- `lifecycle-invalid`: lifecycle is not both successful and consumed.
- `verified`: lifecycle is consumed, all postconditions pass, and no recovery is declared.
- `recovery-required`: lifecycle is consumed, verification fails, and no recovery is declared.
- `recovered`: lifecycle is consumed, verification fails, and recovery is valid.
- `recovery-failed`: a recovery event is present but unexpected or invalid.

## Safety fields

`actionVerified=true` only for `verified`.

`safe=true` only for `verified` and `recovered`.

A `recovered` audit MUST retain `actionVerified=false`.

## Report format

The report begins with:

```text
ZIL-RECOVERY-AUDIT<TAB>1
```

It contains exactly one summary row for each of:

```text
status
outcome
request
lifecycle
action-verified
required
missing
failed
evidence-missing
duplicates
recovery-issues
```

Observed postconditions follow as ordered rows:

```text
postcondition<TAB>name<TAB>pass|fail<TAB>evidence
```

When recovery exists, these rows follow:

```text
recovery-kind
recovery-reference
recovery-completed
recovery-evidence
```

The report ends with one newline.

## Exit contract

The dedicated executable exits:

- `0` when `safe=true`;
- `1` when `safe=false` or evaluation fails;
- `2` when command arguments do not match the supported shape.

## Non-goals

Version 1 does not execute recovery, dereference evidence artifacts, validate external artifact semantics, provide durable transaction isolation, or promote repository evidence into Lean kernel proof or empirical truth.
