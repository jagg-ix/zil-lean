# Capability ownership

This document assigns authority rather than implementation exclusivity. A capability may involve Lean and Clojure while retaining exactly one authoritative decision point.

## Commands

| Capability | Current command | Authority | Operational runtime | Assurance ceiling |
|---|---|---|---|---|
| Parse and validate | worker/control `parse` | Lean | Lean or Clojure-to-Lean | validated |
| Generated Lean source | `compile`, `macro-compile`, worker/control `compile` | Lean | Lean with Clojure workspace preparation | validated |
| Macro expansion | `expand`, `macro-expand`, worker/control `expand` | Lean | Lean with optional Clojure workspace preparation | validated |
| Semantic conformance rows | `conformance`, worker/control `conformance` | Lean | Lean; Clojure compares reports | validated |
| Corpus conformance orchestration | `conformance-suite` | Clojure | JVM plus Lean workers | byte-attested comparison of validated rows |
| Recursive library compilation | `library` | Lean output authority; Clojure plan authority | JVM plus Lean workers | validated output, byte-attested manifest |
| Embedded source compilation | `embedded-native` | Lean output authority; Clojure scan authority | JVM plus Lean workers | validated output, external elaboration evidence |
| Query planning | `query-plan` | Lean | Lean | validated |
| Query governance | `query-ci` | Lean | Lean | validated |
| Query witnesses | `explain-query`, worker/control `query` | Lean | Lean or Clojure-to-Lean | validated |
| Authorization | `authorize`, worker/control `authorize` | Lean | Lean or Clojure-to-Lean | validated |
| Provenance | `trace`, `explain-authorization` | Lean | Lean | validated |
| Dependency graph | `dependency-graph` | Lean | Lean | validated |
| Change impact | `impact`, worker/control `impact` | Lean | Lean or Clojure-to-Lean | validated |
| Formalization scheduling | `formalization-plan`, `formalization-next` | Lean | Lean | validated |
| Agent context | `agent-context` | Lean | Clojure may persist bundles | validated |
| Proof-obligation governance | `proof-obligations` | Lean | external tools produce evidence | validated or externally-attested |
| Theorem and claim audit | `theorem-audit` | Lean | Clojure may collect evidence | kernel-backed or externally-attested |
| Action-token issuance | `action-token` | Lean | Clojure owns durable transaction | validated |
| Checkpoint and consumption | `token-lifecycle` | Lean | Clojure owns compare-and-swap | validated |
| Recovery audit | `recovery-audit`, worker/control `recovery-audit` | Lean | Clojure persists terminal event | validated |
| Formal control-plane routing | `control` | Clojure operational authority | JVM and Lean worker pool | byte-attested transport around Lean result |
| Revision storage | bridge and store APIs | Clojure | SQLite | operational |
| File watching | control-plane service | Clojure | JVM | exploratory |
| Extension discovery and loading | `plugin` | Clojure | JVM | manifest-fingerprinted |
| Extension command dispatch | extension registry | Clojure | JVM | bounded by manifest authority |
| External solver execution | `solver-run` reference extension | External through Clojure | JVM/process | externally-attested |
| Repository scanning | `repository-scan` reference extension | Clojure | JVM | byte-attested |
| Report export | `report-export` reference extension | Clojure | JVM | byte-attested |
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
zil.control.*
zil.store.*
zil.runtime.*
zil.port.*
zil.release.*
zil.bridge.* when coordinating an external runtime or durable store
zil.plugin.*
zil.extensions.*
```

A bridge or extension may translate data into Lean, but translated output is not authoritative until a compiled Lean capability accepts it.

## Formal control-plane boundary

The control plane validates `architecture/capability-ownership.edn` before starting semantic work. It rejects:

- duplicate capability or operation declarations;
- worker operations without ownership entries;
- non-Lean authority for an exchange semantic operation;
- disagreement between capability IDs and the exchange allowlist;
- dispatch after the control plane has closed.

The command table is derived from that validated inventory. Built-in commands are marked nonreplaceable.

## Extension registry boundary

The registry is Clojure-authoritative for loading and operational lifecycle, not for ZIL semantics.

It must:

- validate and fingerprint `ZIL-EXTENSION/1` manifests;
- require runtime-provided capabilities to equal manifest capabilities;
- refuse built-in command or authoritative capability shadowing;
- isolate startup, command, and evidence failures;
- quarantine a failing extension;
- record extension ID and version on every result;
- validate `ZIL-EVIDENCE/1` payload hashes before accepting evidence;
- prevent Clojure extensions from claiming `validated` or `kernel-backed` assurance.

## Reports and evidence

| Report family | Authority |
|---|---|
| `ZILC/1` native semantic rows | Lean |
| `ZIL-CONFORMANCE/1` differential comparison | Clojure comparison over Lean and legacy reports |
| `ZIL-PROVENANCE/1` | Lean |
| `ZIL-CHANGE-IMPACT/1` | Lean |
| `ZIL-AGENT-CONTEXT/1` | Lean |
| `ZIL-ACTION-TOKEN/1` | Lean |
| `ZIL-TOKEN-LIFECYCLE/1` | Lean |
| `ZIL-RECOVERY-AUDIT/1` | Lean |
| `ZIL-EXCHANGE/1` semantic payload | Lean |
| `ZIL-EXCHANGE/1` transport SHA-256 | Clojure client |
| `ZIL-EVIDENCE/1` envelope and byte hashes | Clojure registry/producer |
| external solver result | external producer, represented by Clojure and audited by Lean |
| SQLite transaction receipt | Clojure store |
| Lean declaration/type fingerprint | Lean environment |

## Invariants

1. Only Lean may return `validated` for a ZIL semantic decision.
2. Only a checked Lean declaration may justify `kernel-backed`.
3. Clojure may return `exploratory` or `byte-attested` without Lean, but it must not issue mutation permission.
4. External tool success is evidence, not automatic kernel proof.
5. The Clojure store may reject a valid Lean transition because of concurrent revision change.
6. The store may never commit a transition Lean rejected.
7. Every exchange request declares the capability it expects.
8. Unknown operations and undeclared capabilities fail closed.
9. Transport failure, request invalidity, semantic denial, and successful evaluation are distinct states.
10. One canonical payload is hashed; timestamps and process-local metadata are excluded from semantic fingerprints.
11. Extension command shadowing is forbidden.
12. Extension evidence is rejected if its extension identity, authority, schema, or payload hash is inconsistent.
13. Direct process runners remain test or external-verification injection points, not an alternative semantic authority.

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

A new extension must additionally declare:

- runtime and entrypoint;
- sorted unique provided capabilities;
- required protocols and capabilities;
- input and output schemas;
- command descriptors;
- lifecycle and failure isolation behavior;
- evidence authority and assurance ceiling.

No plugin may replace an existing authoritative capability unless a new protocol version and explicit migration policy are approved.
