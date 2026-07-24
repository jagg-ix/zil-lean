# Durable control event store v1

## Scope

`ZIL-CONTROL-EVENT/1` records operational observations and Lean-authoritative decisions in append-only, expected-revision streams. `ZIL-CONTROL-RECEIPT/1` binds each committed batch to its exact event sequence and final revision.

The event store does not replace the existing domain tables for revisions, leases, checkpoints, actions, action tokens, or outputs. It provides the common audit stream joining those workflows.

## Event envelope

Canonical fields, in order:

```text
schema
event_id
stream
event_type
actor
request_id
base_revision
context_bundle_id
decision_sha256
plugin_id
payload_sha256
payload
```

Required properties:

- `schema` is `ZIL-CONTROL-EVENT/1`;
- `stream`, `event_type`, and `actor` are nonempty;
- `decision_sha256` is `sha256:` plus 64 lowercase hexadecimal digits;
- `payload_sha256` binds canonical JSON payload bytes;
- `event_id` is deterministic unless explicitly supplied;
- timestamps are not part of event identity.

For a Lean operation, `decision_sha256` is the exact attested Lean response payload hash. For an operational-only observation, it is the hash of the exact external evidence or receipt authorizing the observation. It must not be an invented proof claim.

## Stream commit

`append-events!` receives:

```text
database
stream
expected_revision
events
```

The transaction:

1. reads the stream head;
2. rejects when the current revision differs from `expected_revision`;
3. validates and normalizes every event;
4. assigns consecutive revisions;
5. computes the hash chain;
6. writes one immutable batch receipt;
7. writes all events;
8. moves the stream head;
9. commits atomically.

No event is visible when any step fails.

## Hash chain

The first previous digest is:

```text
sha256("")
```

For revision `r`:

```text
event_sha256 = sha256(
  previous_event_sha256 || "\n" ||
  decimal(r) || "\n" ||
  canonical_event_json
)
```

`verify-stream` recomputes every revision and verifies the stored head.

## Receipt

Canonical receipt fields:

```text
schema
receipt_id
stream
base_revision
final_revision
event_count
batch_sha256
committed_at_epoch_ms
```

`batch_sha256` hashes the ordered revision and event-digest pairs. The receipt ID and receipt digest bind the transaction result. A receipt establishes durable byte identity and ordering; it does not upgrade a semantic result to Lean proof.

## Snapshots

A snapshot is immutable for:

```text
stream
revision
reducer_id
```

It records:

- canonical projected state bytes;
- state SHA-256;
- event-chain digest at the snapshot revision.

`ZIL-WORKFLOW-PROJECTION/1` is an operational projection. It records observed event order, actors, request identities, and decision hashes. It does not independently authorize actions or infer safety.

## Control-plane binding

`invoke-and-record!` performs:

```text
Lean exchange decision
  -> validated response identity
  -> control event
  -> expected-revision append
  -> transaction receipt
```

A transport failure creates no event because there is no valid Lean response to bind. A valid Lean denial, unsafe result, or unknown result is recorded as the exact semantic outcome rather than converted into a transport error.

## Workflow observation types

Version 1 recognizes:

```text
context-generated
action-token-issued
checkpoint-created
action-consumed
postcondition-observed
recovery-started
recovery-completed
semantic-decision
external-evidence-recorded
```

These names organize operational projections only. Lean action-token, lifecycle, and recovery modules remain authoritative for transition validity and safety classification.
