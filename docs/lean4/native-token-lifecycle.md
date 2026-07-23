# Native token lifecycle

The native lifecycle auditor replays token issuance, checkpoint binding, and single-use execution from one ZIL source file.

## Command

```bash
bin/zil token-lifecycle \
  examples/token-lifecycle/lifecycle.zc \
  request:issue
```

An optional final path writes the deterministic report.

## States

```text
issued
checkpointed
consumed
```

Transitions are one-way. A consumed token cannot execute again.

## Checkpoint binding

A checkpoint event must satisfy:

- token status is `issued`;
- agent matches the token agent;
- current revision equals the token base revision;
- current time is earlier than token expiry;
- checkpoint ID is nonempty;
- snapshot digest is `sha256:<64 hex>`.

Example:

```zc
request:issue#checkpoint_event@checkpoint:1 [
  checkpoint_id="checkpoint:1",
  agent_id="agent:a",
  current_revision="rev:1",
  snapshot_digest="sha256:...",
  now=120
].
```

## Single-use execution

An execution event must satisfy:

- token status is `checkpointed`;
- checkpoint ID matches the token-bound checkpoint;
- checkpoint and execution revisions equal the token base revision;
- token is not expired;
- store integrity evidence is true;
- current lease agent, module, scope, and revision match the token;
- current lease is active and unexpired;
- action ID is nonempty;
- every observed output has a nonempty artifact ID and SHA-256 hash.

Example:

```zc
request:issue#execution_event@action:1 [
  action_id="action:1",
  checkpoint_id="checkpoint:1",
  current_revision="rev:1",
  now=130,
  store_integrity=true,
  lease_agent_id="agent:a",
  lease_module="Demo",
  lease_scope="src/demo",
  lease_base_revision="rev:1",
  lease_expires_at=180,
  lease_active=true,
  observed_outputs="file:Demo.lean=sha256:..."
].
```

Multiple outputs use `|` separators.

## Failure codes

```text
token-not-issued
token-not-checkpointed
agent-mismatch
context-stale
token-expired
invalid-checkpoint-id
invalid-snapshot-digest
checkpoint-mismatch
store-integrity
lease-mismatch
lease-inactive
lease-expired
invalid-action-id
invalid-observed-output
```

## Report

```text
ZIL-TOKEN-LIFECYCLE/1
status                 pass|fail
request                <node>
issuance               issued|denied
checkpoint-failure     <code or empty>
execution-failure      <code or empty>
token-status           issued|checkpointed|consumed
...
```

A source containing issuance plus a valid checkpoint may pass in `checkpointed` state. A source containing an execution event passes only when the final state is `consumed`.

## Transaction boundary

The native module audits the state-machine contract deterministically. Durable storage still performs transactional token updates, checkpoint insertion, compare-and-swap, and concurrent-consumption protection. The pure state machine makes those conditions reviewable and formally testable.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil token-lifecycle examples/token-lifecycle/lifecycle.zc request:issue
```
