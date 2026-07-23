# ZIL native proof-obligation governance v1

## Source declaration

Required fields:

```text
relation
statement
tool
```

Optional governance fields:

```text
status
criticality
logic
expectation
evidence
artifact_in
artifact_out
proof_token
declaration
waiver_reason
```

Defaults:

```text
status = open
criticality = low
```

## Tools

```text
z3
tlaps
lean4
acl2
manual
```

Only `lean4` is classified as a native backend. This is an execution-domain label, not automatic evidence of discharge.

## Statuses

```text
open
pending
proved
failed
waived
```

## Evaluation

Before status evaluation, the declared relation must occur in a base fact or rule conclusion. Otherwise the verdict is `blocked` with `unknown-relation`.

Status mapping:

```text
failed  -> violated
open    -> blocked
pending -> blocked
proved  -> satisfied only when one or more evidence references exist
waived  -> waived only with a reason and non-critical criticality
```

External open or pending obligations without evidence use:

```text
backend-unavailable-without-evidence
```

Other unresolved open/pending obligations use:

```text
obligation-not-discharged
```

A proved declaration without evidence uses:

```text
proved-status-requires-evidence
```

Waiver failures use:

```text
waiver-reason-missing
critical-obligation-cannot-be-waived
```

## Evidence references

Evidence is the unique ordered union of nonempty values under:

```text
evidence
artifact_in
artifact_out
proof_token
declaration
```

The governance layer validates presence, not the content of external artifacts.

## Report

```text
ZIL-PROOF-OBLIGATIONS\t1
status\t<pass|fail>
module\t<module>
tool-filter\t<tool|all>
count\t<count>
satisfied\t<count>
violated\t<count>
blocked\t<count>
waived\t<count>
obligation\t<id>\t<relation>\t<tool>\t<status>\t<criticality>\t<verdict>\t<known|unknown>\t<native|external>\t<evidence>\t<reasons>\t<statement>
```

## Success

The report passes exactly when:

```text
violated = 0
blocked = 0
```

Waived obligations do not block unless waiver validation failed. An empty selected set passes.

## Scope

The command governs declared status and evidence references. External solver replay, artifact authentication, and Lean kernel validation remain responsibilities of their producing systems.
