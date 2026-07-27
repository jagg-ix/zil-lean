# ZIL assurance levels v1

## Purpose

Assurance labels state what checked a result. They do not rank the importance of a result and must not be inferred from a successful exit code alone.

## Levels

### `exploratory`

The result was produced from cached, incomplete, plugin-provided, or control-plane data without an authoritative Lean evaluation.

Permitted uses:

- navigation;
- editor hints;
- source generation;
- planning;
- cached project inspection.

Forbidden uses:

- action-token issuance;
- mutation authorization;
- declaration of a safe terminal action state;
- promotion to kernel evidence.

### `validated`

The request was accepted by the native Lean ZIL engine and the semantic payload was produced by an authoritative capability handler.

This means the requested ZIL operation completed under its declared assumptions. It does not mean an external scientific claim is true or that an external artifact was independently replayed.

### `kernel-backed`

The evidence identifies a Lean declaration accepted by the current Lean environment and carries the declaration identity and type fingerprint required by the relevant contract.

This level applies only to the exact checked statement. It does not automatically cover documentation, interpretation, empirical claims, or stronger statements.

### `externally-attested`

An external tool, service, repository operation, or artifact producer supplied evidence whose identity and status were recorded and audited.

The evidence may support a proof obligation or release decision, but it is not Lean kernel evidence unless a separate Lean declaration establishes the relevant statement.

### `byte-attested`

A transport or store component computed and recorded a cryptographic digest over exact canonical bytes.

Byte identity does not establish semantic correctness. A response may be both `validated` and `byte-attested` through separate fields.

## Composition

An exchange response has one semantic assurance label and may carry additional evidence rows. For example:

```text
semantic assurance: validated
transport evidence: byte-attested sha256:...
external evidence: externally-attested artifact:solver-report
kernel evidence: none
```

## Prohibited promotions

The following promotions are invalid without additional evidence:

```text
exploratory -> validated
validated -> kernel-backed
externally-attested -> kernel-backed
byte-attested -> validated
```

A Clojure client may add byte attestation to a Lean response. It may not change the semantic assurance returned by Lean.

## Failure behavior

- Invalid protocol requests have no assurance.
- Unsupported capabilities have no assurance.
- A successful authorization evaluation that returns deny remains `validated`; denial is a semantic result, not a transport failure.
- A successful recovery audit that returns unsafe remains `validated`.
- A worker crash or malformed response is a transport failure and must not be represented as a semantic denial.
