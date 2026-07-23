# ZIL hybrid system architecture

## Decision

ZIL is a deliberately hybrid system.

- Lean is the authoritative semantic and verification kernel.
- Clojure is the operational control plane.
- A versioned, language-neutral exchange protocol connects both runtimes.
- A Lean-only profile remains supported for embedding and high-assurance local use.
- A Clojure-only process may explore cached or unverified state, but it cannot issue authoritative mutation or safety decisions.

The goal is not to remove either runtime. The goal is to assign one authority to every invariant and prevent two implementations from silently disagreeing about meaning.

## System planes

```text
user interfaces
  CLI | REPL | editor | API | agents
        |
        v
Clojure control plane
  workspace discovery
  process and worker supervision
  SQLite transactions and DataScript projections
  plugins and external-tool adapters
  release and workflow orchestration
        |
        | ZIL-EXCHANGE/1 JSON Lines
        v
Lean authoritative kernel
  parsing and macro expansion
  rule safety, stratification, and checked closure
  query witnesses, authorization, provenance, and impact
  theorem and claim boundaries
  agent context and mutation safety contracts
        |
        v
external evidence plane
  Git | compilers | Z3 | TLAPS | ACL2 | document and service adapters
```

## Lean authority

Lean is authoritative for:

- ZIL syntax trees and structural validity;
- macro expansion semantics;
- rule safety and stratification;
- checked closure and query semantics;
- authorization decisions;
- derivation provenance and change-impact semantics;
- theorem, proof-obligation, and external-claim classification;
- canonical agent-context bytes;
- action-token issuance;
- checkpoint and single-use lifecycle transitions;
- postcondition and recovery classification;
- canonical native reports.

A caller may cache or index Lean results. It may not replace them with an independently interpreted result while retaining a kernel-backed assurance label.

## Clojure authority

Clojure is authoritative for:

- repository and workspace discovery;
- file watching and interactive project services;
- plugin loading and capability registration;
- external process execution and supervision;
- worker lifecycle, pooling, timeouts, and restart policy;
- durable SQLite transactions;
- DataScript projections and exploratory indexes;
- connectors to editors, repositories, services, and external proof tools;
- workflow, release, and artifact orchestration;
- transport-level SHA-256 attestation.

Clojure may produce evidence for Lean to audit. External evidence is not automatically promoted to Lean kernel evidence.

## Shared protocol assets

The following directories are runtime-neutral contracts:

```text
spec/
architecture/
examples/exchange/
```

They define protocol schemas, capability identifiers, assurance levels, deterministic reports, extension manifests, fixtures, and failure codes.

## One authority per invariant

Each capability is assigned one of four authorities:

- `lean`: semantic or safety authority;
- `clojure`: operational authority;
- `shared`: language-neutral schema or fixture;
- `external`: an external system whose result must be represented as evidence.

A capability can use both runtimes without having two authorities. For example, Clojure opens a transaction and sends a request; Lean decides whether the state transition is valid; Clojure commits only if the revision remains current.

## Deployment profiles

### Lean SDK

Lean, Lake, the `Zil` library, and native executables. Suitable for Lean projects, deterministic verification, and constrained environments.

### Full workbench

Clojure/JVM control plane, Lean workers, SQLite, and plugins. This is the complete interactive and extensible system.

### Service

A supervised Clojure daemon, a Lean worker pool, durable event storage, remote APIs, and agent scheduling.

### Exploratory Clojure

May inspect cached data, edit source, and generate requests while Lean is unavailable. Results must be labeled `exploratory`; mutation tokens and safe terminal outcomes are unavailable.

## Trust boundary

The Lean kernel establishes only the exact statements and decisions it checks. Clojure transport attestation establishes byte identity and process provenance. External tools establish results under their own assumptions. ZIL reports preserve these distinctions instead of collapsing them into one generic `proved` state.
