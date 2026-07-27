# D-MetaVM Core v0.1 (ZIL-First)

Status: Draft (normative for model shape and semantics).

This document defines a ZIL-first core specification for a distributed meta-VM
("D-MetaVM") inspired by EVM execution structure but explicitly detached from
blockchain/cryptocurrency semantics.

## 1. Scope

This spec defines:

- a single-node execution core (stack, memory, storage, pc, budget, code),
- a meta-interpreter layer (register and execute foreign runtimes),
- a distributed message-passing layer (multi-node asynchronous execution),
- required safety/liveness contracts for formal backends (Z3/TLA+/Lean4).

This spec is intended to be implemented as canonical ZIL facts/rules/macros and
then exported to formal backends.

## 2. Explicit Non-Goals

The core language profile MUST NOT require or imply:

- native token economics,
- mining / proof-of-work,
- global ledger state,
- consensus protocol embedded in VM semantics.

Any such mechanism is outside this core and, if needed, MUST be modeled as an
external provider/profile layer.

## 3. Canonical Entity Vocabulary

The model MUST use canonical entities (prefix illustrative, not mandatory):

- `dmetavm_node`
- `dmetavm_channel`
- `dmetavm_interpreter`
- `dmetavm_registration`
- `dmetavm_exec_step`
- `dmetavm_message`
- `dmetavm_profile`

Recommended core relations:

- node runtime:
  - `#engine@value:<engine>`
  - `#mode@value:<mode>`
  - `#memory_model@value:<memory_model>`
  - `#stack_model@value:<stack_model>`
  - `#jump_control@value:<jump_control>`
- interpreter registry:
  - registration `#node@<node>`
  - registration `#interpreter@<interpreter>`
- execution step:
  - `#node@<node>`
  - `#opcode_class@value:<class>`
  - `#pc_before@value:<pc>`
  - `#pc_after@value:<pc>`
  - `#budget_cost@value:<n>`
- message:
  - `#from@<node>`
  - `#to@<node>`
  - `#msg_kind@value:<kind>`
  - `#channel@<channel>`
  - `#payload@value:<payload>`
  - `#status@value:<status>`

## 4. Core Semantics (Datalog-First)

### 4.1 Single-Node Core Step

For each node, a core step MUST model:

- opcode category execution,
- `pc` transition (`pc_before`, `pc_after`),
- budget charge (`budget_cost`),
- halt/fault outcomes when constraints fail.

Models SHOULD encode at least: arithmetic, jump, memory, return classes.

### 4.2 Meta-Interpreter

The meta layer MUST support:

- interpreter declaration (`dmetavm_interpreter`),
- per-node registration (`dmetavm_registration`),
- execution request messages with `msg_kind = exec_remote` or equivalent.

The foreign interpreter payload is opaque at this layer and treated as data.

### 4.3 Distributed Execution

The distributed layer MUST model:

- at least 2 nodes,
- explicit channels between nodes,
- asynchronous message lifecycle (`issued -> accepted -> completed|failed`),
- compatibility with non-deterministic interleaving.

## 5. Required Formal Contracts

Conforming models MUST declare:

- at least one `LTS_ATOM` for node/core lifecycle,
- at least one `LTS_ATOM` for message lifecycle,
- `POLICY` constraints for:
  - non-negative budget,
  - pc bound sanity,
  - no-blockchain profile flags,
  - message integrity envelope.

Recommended additional policy:

- TM-surface readiness contract requiring tape-like memory, jump control, and
  finite-state encoding capacity.

## 6. Evmone Application Profile (Informative, Optional)

When applying this model to `evmone`:

- core step maps to `baseline_execution` / `advanced_execution`,
- analysis maps to `advanced_analysis`,
- state carrier maps to `ExecutionState`,
- host call boundary maps to EVMC host calls (`instructions_calls` path).

This profile remains blockchain-free by constraining model flags rather than by
changing evmone internals in this spec.

## 7. Conformance

A model conforms to D-MetaVM Core v0.1 when:

1. It instantiates the canonical entity vocabulary (or equivalent aliases
   lowered to equivalent facts).
2. It encodes core + meta + distributed layers.
3. It includes required LTS and POLICY declarations.
4. It can be evaluated by ZIL runtime and exported to at least one formal
   backend (`export-tla` or `export-lean`) without schema loss.

