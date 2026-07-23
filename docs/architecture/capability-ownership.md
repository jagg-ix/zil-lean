# Capability ownership

This document assigns authority rather than implementation exclusivity. A capability may involve Lean and Clojure while retaining exactly one authoritative decision point.

## Commands

| Capability | Current command | Authority | Operational runtime | Assurance ceiling |
|---|---|---|---|---|
| Parse and validate | `compile`, worker `parse` | Lean | Lean or Clojure-to-Lean | validated |
| Macro expansion | `expand`, `macro-expand`, worker `expand` | Lean | Lean with optional Clojure workspace preparation | validated |
| Generated Lean source | `compile`, `macro-compile` | Lean | Lean | validated |
| Query planning | `query-plan` | Lean | Lean | validated |
| Query governance | `query-ci` | Lean | Lean | validated |
| Query witnesses | `explain-query`, worker `query` | Lean | Lean or Clojure-to-Lean | validated |
| Authorization | `authorize`, worker `authorize` | Lean | Lean or Clojure-to-Lean | validated |
| Provenance | `trace`, `explain-authorization` | Lean | Lean | validated |
| Dependency graph | `dependency-graph` | Lean | Lean | validated |
| Change impact | `impact`, worker `impact` | Lean | Lean or Clojure-to-Lean | validated |
| Formalization scheduling | `formalization-plan`, `formalization-next` | Lean | Lean | validated |
| Agent context | `agent-context` | Lean | Clojure may persist bundles | validated |
| Proof-obligation governance | `proof-obligations` | Lean | external tools produce evidence | validated or externally-attested |
| Theorem and claim audit | `theorem-audit` | Lean | Clojure may collect evidence | kernel-backed or externally-attested |
| Action-token issuance | `action-token` | Lean | Clojure owns durable transaction | validated |
| Checkpoint and consumption | `token-lifecycle` | Lean | Clojure owns compare-and-swap | validated |
| Recovery audit | `recovery-audit`, worker `recovery-audit` | Lean | Clojure persists terminal event | validated |
| Revision storage | bridge and store APIs | Clojure | SQLite | operational |
| File watching | control-plane service | Clojure | JVM | exploratory |
| Plugin loading | extension registry | Clojure | JVM | depends on produced evidence |
| External solver execution | adapters | External through Clojure | JVM/process | externally-attested |
| Release orchestration | release attestation | Clojure orchestration, Lean evidence authority | JVM plus Lean workers | externally-attested or kernel-backed by row |
| Transport digest | exchange client | Clojure | JVM SHA-256 | byte-attested |

## Module ownership

### Lean semantic kernel

```text
Zil.Core.*
Zil.Parser.*
Zil.Engine.*
Zil.Authorization
Zil.QueryGovernance
Zil.Impact
Zil.Formalization
Zil.AgentContext
Zil.ProofObligation
Zil.TheoremAudit
Zil.ActionToken
Zil.TokenLifecycle
Zil.RecoveryAudit
Zil.Exchange.*
```

### Clojure control plane

```text
zil.worker.*
zil.store.*
zil.runtime.*
zil.port.*
zil.release.*
zil.bridge.* when coordinating an external runtime or durable store
zil.plugin.*
```

A bridge may translate data into Lean, but translated output is not authoritative until the Lean worker accepts it.

## Reports and evidence

| Report family | Authority |
|---|---|
| `ZIL-CONFORMANCE/1` native semantic rows | Lean |
| `ZIL-PROVENANCE/1` | Lean |
| `ZIL-CHANGE-IMPACT/1` | Lean |
| `ZIL-AGENT-CONTEXT/1` | Lean |
| `ZIL-ACTION-TOKEN/1` | Lean |
| `ZIL-TOKEN-LIFECYCLE/1` | Lean |
| `ZIL-RECOVERY-AUDIT/1` | Lean |
| `ZIL-EXCHANGE/1` semantic payload | Lean |
| `ZIL-EXCHANGE/1` transport SHA-256 | Clojure client |
| external solver artifact | external producer, audited by Lean |
| SQLite transaction receipt | Clojure store |
| Lean declaration/type fingerprint | Lean environment |

## Invariants

1. Only Lean may return `validated` for a ZIL semantic decision.
2. Only a checked Lean declaration may justify `kernel-backed`.
3. Clojure may return `exploratory` without Lean, but it must not issue mutation permission.
4. External tool success is evidence, not automatic kernel proof.
5. The Clojure store may reject a valid Lean transition because of concurrent revision change.
6. The store may never commit a transition Lean rejected.
7. Every exchange request declares the capability it expects.
8. Unknown operations and undeclared capabilities fail closed.
9. Transport failure, request invalidity, semantic denial, and successful evaluation are distinct states.
10. One canonical payload is hashed; timestamps and process-local metadata are excluded from semantic fingerprints.

## Change procedure

A new capability must declare:

- authority;
- operation identifier;
- required capability token;
- request and response schema version;
- assurance level;
- deterministic payload contract;
- persistence effects, if any;
- external evidence roles;
- failure classification.

No plugin may replace an existing authoritative capability unless a new protocol version and explicit migration policy are approved.
