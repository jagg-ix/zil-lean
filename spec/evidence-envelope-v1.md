# ZIL evidence envelope v1

## Scope

`ZIL-EVIDENCE/1` records an extension-produced artifact without promoting it beyond the authority and assurance of its producer.

The envelope is created and byte-attested by the Clojure control plane. Lean may later audit or consume the referenced evidence through a separate compiled capability.

## Fields

```json
{
  "schema": "ZIL-EVIDENCE/1",
  "evidence_id": "evidence:<64 hex>",
  "extension_id": "extension:external-solver",
  "extension_version": "1.0.0",
  "authority": "external",
  "assurance": "externally-attested",
  "role": "external-proof-tool",
  "subject": "obligation:termination",
  "input_sha256": "sha256:<64 hex>",
  "output_sha256": "sha256:<64 hex>",
  "payload": "...",
  "metadata": {}
}
```

All fields are required.

## Identity

`evidence_id` is deterministic:

```text
sha256(
  extension_id + newline +
  extension_version + newline +
  role + newline +
  subject + newline +
  input_sha256 + newline +
  output_sha256
)
```

The identifier is prefixed with `evidence:`.

The envelope excludes timestamps and process-local identifiers from its canonical identity.

## Byte binding

- `input_sha256` identifies the bytes supplied to the extension or an extension-defined deterministic aggregate of those inputs.
- `output_sha256` is exactly SHA-256 of the UTF-8 `payload` bytes.
- The registry recomputes `output_sha256` before accepting returned evidence.
- Nested metadata maps are emitted in deterministic key order.

## Authority and assurance

Permitted assurance labels are:

- `exploratory`;
- `byte-attested`;
- `externally-attested`;
- `validated`;
- `kernel-backed`.

A Clojure extension MUST NOT create `validated` or `kernel-backed` evidence.

An external-tool adapter normally uses:

```text
authority = external
assurance = externally-attested
```

A repository scanner or report exporter normally uses:

```text
authority = clojure
assurance = byte-attested
```

Lean evidence may carry `validated` or `kernel-backed` only when a configured Lean capability supplies the exact checked statement or decision.

## Registry checks

Before evidence is returned to a caller, the extension registry MUST verify:

1. schema is exactly `ZIL-EVIDENCE/1`;
2. evidence ID has the expected form;
3. input and output digest forms are valid;
4. output digest matches payload bytes;
5. assurance is recognized;
6. extension ID equals the registered extension;
7. authority equals the registered manifest authority.

A violation quarantines the extension and fails the invocation.

## Non-goals

The envelope does not:

- prove the semantic truth of an external result;
- make a Clojure computation Lean-validated;
- replace an action token or authorization decision;
- establish durable transaction ordering;
- dereference or independently replay the recorded artifact.
