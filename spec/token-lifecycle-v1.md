# ZIL native token lifecycle v1

## State

```lean
inductive Status where
  | issued
  | checkpointed
  | consumed
```

```lean
structure State where
  token : ActionToken.Token
  lease : ActionToken.Lease
  status : Status
  checkpoint : Option Checkpoint
  execution : Option Execution
```

## Initialization

A lifecycle may be initialized only from an allowed issuance decision containing a token.

## Checkpoint transition

`issued -> checkpointed` requires:

```text
request agent = token agent
request current revision = token base revision
request now < token expiry
checkpoint ID nonempty
snapshot digest is sha256:<64 hex>
```

On success, the checkpoint stores ID, agent, revision, digest, and creation time.

## Execution transition

`checkpointed -> consumed` requires:

```text
checkpoint exists
request checkpoint ID = bound checkpoint ID
request and checkpoint revisions = token base revision
request now < token expiry
store_integrity = true
lease agent/module/scope/revision match token
lease active = true
request now < lease expiry
action ID nonempty
every observed output has artifact and sha256:<64 hex>
```

On success, execution stores action ID, checkpoint ID, revision, execution time, and ordered outputs.

No transition exits `consumed`. A second execution attempt therefore fails with `token-not-checkpointed`.

## Source events

Checkpoint relation:

```text
<request>#checkpoint_event@<checkpoint> [attributes]
```

Execution relation:

```text
<request>#execution_event@<action> [attributes]
```

At most the first semantic fact for each event relation is consumed by v1.

## Audit behavior

The audit first decodes and evaluates `action_token_request`, then applies an optional checkpoint event and optional execution event.

```text
issuance denied                  -> fail
checkpoint transition failure    -> fail
execution transition failure     -> fail
valid checkpoint only            -> pass, checkpointed
valid checkpoint and execution   -> pass, consumed
issuance only                     -> fail, issued
```

## Report

```text
ZIL-TOKEN-LIFECYCLE\t1
status\t<pass|fail>
request\t<node>
issuance\t<issued|denied>
checkpoint-failure\t<code or empty>
execution-failure\t<code or empty>
token-status\t<issued|checkpointed|consumed>
```

Checkpoint and execution rows are appended when present.

## Exit status

```text
0 lifecycle audit passed
1 lifecycle audit failed or evaluation error
2 invalid command form
```

## Concurrency boundary

This specification models valid transitions. Durable compare-and-swap remains required to prevent two processes from consuming the same persisted token concurrently.
