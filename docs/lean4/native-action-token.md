# Native action-token issuance

The native Lean layer can audit and issue a short-lived action token from one attributed ZIL request.

## Command

```bash
bin/zil action-token \
  examples/action-token/request.zc \
  request:issue
```

An optional final path writes the deterministic report.

## Context binding

The request must contain:

```text
context_bundle_id = sha256:<64 hexadecimal digits>
```

This value is the SHA-256 of the exact `ZIL-AGENT-CONTEXT/1` bytes reviewed by the agent before mutation. A token is therefore bound to one task, agent, scope, impact set, relevant fact set, query set, and formalization-target set.

## Required evidence

All of these booleans must be true:

```text
context_fresh
context_complete
no_critical_conflict
authorized
valid_lease
preconditions_pass
recovery_available
store_integrity
```

The native contract also independently checks:

- nonempty token, task, agent, module, revision, scope, and lease identifiers;
- base revision equals current revision;
- lease agent, module, scope, and revision match the request;
- lease is active and not expired;
- positive token TTL;
- nonempty action type and target;
- rollback or compensation kind with a nonempty reference.

The resulting expiration is:

```text
min(now + ttl_seconds, lease_expires_at)
```

## Request form

```zc
request:issue#action_token_request@entity:request [
  token_id="acttok:1",
  task_id="task:demo",
  agent_id="agent:a",
  module="Demo",
  base_revision="rev:1",
  current_revision="rev:1",
  scope="src/demo",
  lease_id="lease:1",
  context_bundle_id="sha256:...",
  now=120,
  ttl_seconds=60,
  lease_agent_id="agent:a",
  lease_module="Demo",
  lease_scope="src/demo",
  lease_base_revision="rev:1",
  lease_expires_at=150,
  lease_active=true,
  action_type="modify_file",
  action_target="file:Demo.lean",
  expected_effects="compile|update_index",
  required_postconditions="file_compiles|index_matches",
  rollback_kind="rollback",
  rollback_reference="git:abc",
  context_fresh=true,
  context_complete=true,
  no_critical_conflict=true,
  authorized=true,
  valid_lease=true,
  preconditions_pass=true,
  recovery_available=true,
  store_integrity=true
].
```

List-valued text fields use `|` separators because tuple attributes are scalar.

## Failure ordering

Failures are deterministic. Resolved evidence failures are reported first, followed by durable revision/lease failures, TTL and bundle validation, identity/action validation, and rollback validation.

## Report

```text
ZIL-ACTION-TOKEN/1
status    issued|denied
request   <node>
failures  <comma-separated codes>
...
```

Issued reports include the complete token payload, action intent, rollback plan, issue and expiry times, required postconditions, and `required-checkpoint=true`.

## Scope boundary

This module evaluates the native issuance contract. The durable Clojure/SQLite layer remains responsible for compare-and-swap persistence, uniqueness, lease ownership, and replay-integrity checks at the storage boundary. A later native lifecycle layer audits checkpoint and execution transitions.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil action-token examples/action-token/request.zc request:issue
```
