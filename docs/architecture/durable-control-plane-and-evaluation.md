# Durable control plane and runtime evaluation

## Phase 5: durable agent and control-plane state

The formal control plane now has an append-only audit stream in addition to the existing domain tables for revisions, leases, checkpoints, actions, tokens, and outputs.

```text
Lean-authoritative decision
        |
        v
validated exchange response
        |
        v
ZIL-CONTROL-EVENT/1
        |
        v
expected-revision SQLite transaction
        |
        +--> ZIL-CONTROL-RECEIPT/1
        |
        +--> hash-chained stream head
        |
        `--> immutable workflow snapshot
```

### Authority

Lean remains authoritative for:

- authorization;
- action-token issuance;
- checkpoint and lifecycle validity;
- postcondition and recovery classification;
- semantic payloads and assurance.

Clojure remains authoritative for:

- expected-revision compare-and-swap;
- event ordering;
- atomic transaction commit;
- hash-chain integrity;
- transaction receipts;
- operational projections and snapshots.

An operational projection does not reinterpret a Lean decision. It preserves the exact decision hash and selected response fields.

### Durable invocation

```clojure
(require '[zil.control.durable :as durable]
         '[zil.control.runtime :as control])

(def plane (control/start! {:pool-size 2}))

(def result
  (durable/invoke-and-record!
   plane
   "var/zil-control.sqlite"
   {:stream "workflow:release"
    :expected-revision 0
    :actor "agent:reviewer"
    :command "authorize"
    :input-path "examples/authorization/access.zc"
    :arguments ["doc:readme" "viewer" "user:11"]
    :workflow-id "workflow:release"}))

(control/stop! plane)
```

A valid denial is recorded. A transport failure is not recorded because no trustworthy Lean response exists.

### CLI

```bash
bin/zil control-store invoke \
  var/zil-control.sqlite \
  workflow:release \
  0 \
  agent:reviewer \
  authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Inspect and verify:

```bash
bin/zil control-store status var/zil-control.sqlite workflow:release
bin/zil control-store verify var/zil-control.sqlite workflow:release
bin/zil control-store project var/zil-control.sqlite workflow:release
```

Record an already validated workflow observation:

```bash
bin/zil control-store record \
  var/zil-control.sqlite \
  workflow:release \
  1 \
  agent:executor \
  action-consumed \
  sha256:<decision-digest> \
  event.edn
```

The EDN payload should include `workflow_id` or a request identity and any domain identifiers such as `token_id` or `action_id`.

### StoreBackend extension

The reference extension is:

```text
extensions/reference/sqlite-event-store/extension.json
```

It implements `StoreBackend` and provides:

```text
control-event-store
snapshot-store
```

It also exposes operational status and projection commands through the extension registry.

## Phase 6: measured language placement

The next architecture decision is not “remove Clojure” or “move everything to Lean.” Each component is evaluated from evidence.

```bash
bin/zil evaluate-runtime
```

With no measurements, the report marks every component `insufficient-evidence`.

Supply measurements:

```bash
bin/zil evaluate-runtime \
  --model architecture/runtime-evaluation.edn \
  --measurements examples/evaluation/runtime-measurements.edn \
  --output generated/architecture-evaluation.edn
```

### Evaluation dimensions

```text
correctness
latency
throughput
maintenance
extensibility
proof-coverage
reliability
deployment-simplicity
```

Every measurement includes a normalized value, confidence, sample count, and source identifier.

### Hard constraints

Scores cannot override system invariants.

- Semantic or safety components requiring kernel evidence cannot become Clojure-only.
- Components requiring dynamic runtime plugins cannot become Lean-only.
- Components required by the Lean SDK profile cannot become Clojure-only.

### Outcomes

```text
insufficient-evidence
review-required
retain-current
candidate-change
```

A `candidate-change` report is advisory and requires explicit human approval. The evaluator does not modify code, manifests, command routing, or capability ownership.

## Relationship to existing storage

The new control stream complements, rather than replaces:

```text
module_heads
batches
operations
snapshots
authorizations
leases
checkpoints
actions
action_tokens
checkpoint_tokens
action_outputs
```

Those tables remain optimized domain state. The control stream joins decisions and operational observations across those domains into a common append-only audit history.

## Failure distinctions

The system preserves separate states for:

- transport failure;
- request invalidity;
- semantic denial;
- unsafe recovery;
- revision conflict;
- transaction rollback;
- hash-chain failure;
- insufficient architecture evidence;
- human-reviewed placement change.

These states must not be collapsed into a generic pass/fail result.
