# ZIL native action token v1

## Input relation

One request is a ground relation:

```text
<request>#action_token_request@entity:request [attributes]
```

Required scalar attributes:

```text
token_id
task_id
agent_id
module
base_revision
current_revision
scope
lease_id
context_bundle_id
now
ttl_seconds
lease_agent_id
lease_module
lease_scope
lease_base_revision
lease_expires_at
lease_active
action_type
action_target
rollback_kind
rollback_reference
context_fresh
context_complete
no_critical_conflict
authorized
valid_lease
preconditions_pass
recovery_available
store_integrity
```

Optional text attributes:

```text
expected_effects
required_postconditions
```

Their values are `|`-separated lists.

## Context bundle identifier

A valid context bundle ID is exactly:

```text
sha256:<64 hexadecimal digits>
```

It identifies the exact canonical `ZIL-AGENT-CONTEXT/1` bytes used during preflight.

## Issuance conditions

Issuance succeeds exactly when:

```text
all evidence booleans are true
base_revision = current_revision
lease identity/module/scope/revision match request
lease_active = true
now < lease_expires_at
ttl_seconds > 0
context_bundle_id is valid
all identity fields are nonempty
action type and target are nonempty
rollback kind is rollback or compensation
rollback reference is nonempty
```

## Expiration

```text
expires_at = min(now + ttl_seconds, lease_expires_at)
```

## Failures

```text
context-fresh
context-complete
no-critical-conflict
authorized
valid-lease
preconditions-pass
recovery-available
store-integrity
context-stale
lease-mismatch
lease-inactive
lease-expired
invalid-token-ttl
invalid-context-bundle-id
invalid-identity
invalid-action
missing-rollback
```

Failures retain the evaluation order above and are not deduplicated because each check is unique.

## Report

```text
ZIL-ACTION-TOKEN\t1
status\t<issued|denied>
request\t<node>
failures\t<codes>
```

Issued reports append the full token payload and terminate with:

```text
required-checkpoint\ttrue
```

## Exit status

```text
0 token issued
1 request denied or evaluation error
2 invalid command form
```

## Trust boundary

The report is a pure native decision over supplied evidence. Durable persistence and transactional compare-and-swap enforcement remain external storage responsibilities.
