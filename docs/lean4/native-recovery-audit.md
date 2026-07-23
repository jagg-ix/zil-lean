# Native postcondition verification and recovery audit

`Zil.RecoveryAudit` closes the native mutation-safety sequence after action-token issuance and single-use execution. It replays the declared lifecycle, verifies the required postconditions carried by the issued token, and audits any precommitted rollback or compensation event.

## Command

```bash
bin/zil recovery-audit \
  examples/recovery-audit/recovered.zc \
  request:issue
```

An optional third argument writes the report to a file. `-` selects standard output.

The command exits with:

- `0` when the action is directly `verified` or a required recovery is valid and `recovered`;
- `1` when the lifecycle is invalid, recovery is required, or recovery failed;
- `2` for an invalid command shape.

## Source declarations

The request node must already carry the action-token, checkpoint, and execution events consumed by `Zil.TokenLifecycle`.

Required postconditions are taken from the issued token's `required_postconditions` field. Each observation uses:

```zil
request:issue#postcondition_event@post:file_compiles [
  passed=true,
  evidence="artifact:lean-elaboration-report"
].
```

The object name after `post:` is the exact required-postcondition identifier. A passing observation requires a nonempty evidence reference. Every required name must occur exactly once.

When verification fails, recovery is evaluated against the rollback or compensation precommitted in the issued token:

```zil
request:issue#recovery_event@recovery:42 [
  kind="rollback",
  reference="git:checkpoint-42",
  completed=true,
  evidence="artifact:rollback-report"
].
```

The recovery kind and reference must match the token exactly. The event must be complete and carry evidence.

## Outcomes

`verified`
: The lifecycle reached `consumed`; every required postcondition occurred exactly once, passed, and carried evidence; no recovery event was supplied.

`recovery-required`
: The lifecycle was consumed, but at least one postcondition is missing, failed, lacks evidence, or is duplicated, and no recovery event was supplied.

`recovered`
: Verification failed, but the declared recovery event exactly matches the precommitted rollback or compensation and completed with evidence.

`recovery-failed`
: Recovery was unexpected, mismatched, incomplete, or lacked evidence.

`lifecycle-invalid`
: The token lifecycle did not reach a valid consumed state. Postcondition evidence cannot make such an action safe.

## Report

The deterministic `ZIL-RECOVERY-AUDIT/1` report records:

- terminal safety and outcome;
- lifecycle and direct-verification status;
- required and observed postconditions;
- missing, failed, evidence-missing, and duplicate names;
- recovery kind, reference, completion, evidence, and consistency issues.

A recovered action is marked safe, but `action-verified` remains false. This preserves the distinction between successful execution and successful containment.

## Trust and durability boundaries

The native audit validates declared repository evidence and internal consistency. It does not independently execute a rollback, inspect an external artifact, or prove an empirical claim.

Durable storage remains responsible for append-only event persistence, transaction ordering, and preventing recovery records from being rewritten after audit.
