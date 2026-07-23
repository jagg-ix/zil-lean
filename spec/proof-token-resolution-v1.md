# ZIL proof token resolution v1

## Token batch

```json
{
  "format": "zil.proof-tokens.v0.1",
  "complete": true,
  "module": "Demo",
  "token_count": 1,
  "tokens": [{
    "token_id": "proof:answer",
    "declaration": "Demo.answer",
    "expected_kind": "theorem",
    "acceptable_trust": ["kernel_checked_term"],
    "claim": "answer-is-valid"
  }]
}
```

Token IDs are unique. The module and declaration fields are nonempty. `expected_kind`, `acceptable_trust`, and `claim` are optional.

## Lean authority

Resolution accepts only a complete `zil.lean-events.v0.1` batch. The token-batch module must equal the event-batch module.

## Resolved declaration

One declaration resolves when:

```text
exactly one event matches declaration
event.module equals token-batch.module
expected_kind is absent or equals event.kind
event.kernel_present is true
event.uses_sorry is false
event.trust is included in acceptable_trust
event.type_fingerprint is nonempty
```

The default accepted trust set is:

```text
kernel_checked_term
```

## Report

```json
{
  "format": "zil.proof-token-resolution.v0.1",
  "ok": true,
  "module": "Demo",
  "lean_version": "4.32.0",
  "event_batch_fingerprint": "sha256:...",
  "token_batch_fingerprint": "sha256:...",
  "token_count": 1,
  "resolved": 1,
  "unresolved": 0,
  "status_counts": {"resolved": 1},
  "resolutions": [{
    "token_id": "proof:answer",
    "declaration": "Demo.answer",
    "status": "resolved",
    "module": "Demo",
    "kind": "theorem",
    "trust": "kernel_checked_term",
    "kernel_present": true,
    "uses_sorry": false,
    "type_fingerprint": "lean-hash:answer-v1",
    "dependencies": ["Nat"]
  }]
}
```

Canonical output converts keyword keys and values to ordinary JSON strings. It never emits colon-prefixed field names.

## Failure states

```text
missing
ambiguous
module_mismatch
kind_mismatch
kernel_missing
uses_sorry
trust_mismatch
fingerprint_missing
```

`:ok` is true exactly when every token has `resolved` status. Every resolved row is immediately eligible for theorem statement locking.

## Claim boundary

An optional token claim is copied with:

```text
claim_status = external_unproved
```

Resolution never writes `proved_claim=true` and never constructs a Lean proof term.
