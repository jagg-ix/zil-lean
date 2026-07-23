# ZIL exchange protocol v1

## Transport

`ZIL-EXCHANGE/1` uses UTF-8 JSON Lines. One line is one complete request or response. A worker may process one request and exit or remain alive until standard input closes.

The Lean worker never evaluates an arbitrary command string. It dispatches only compiled operation identifiers.

## Request

```json
{
  "schema": "ZIL-EXCHANGE/1",
  "request_id": "request:123",
  "protocol_version": 1,
  "operation": "authorize",
  "input_path": "examples/authorization/access.zc",
  "base_revision": "rev:42",
  "input_sha256": "sha256:...",
  "capabilities": ["authorization-v1"],
  "arguments": ["doc:readme", "viewer", "user:11"]
}
```

All fields are required in version 1.

- `request_id` is nonempty and unique in the caller's execution scope.
- `protocol_version` is exactly `1`.
- `input_path` identifies a workspace-controlled file.
- `base_revision` is `-` when the operation is not revision-bound.
- `input_sha256` is computed by the Clojure client over the exact input bytes. The initial Lean worker carries this binding but does not independently recompute it.
- `capabilities` is sorted and unique in canonical requests.
- `arguments` contains operation-specific strings.

## Operations

| Operation | Required capability | Arguments | Semantic payload |
|---|---|---|---|
| `parse` | `parse-v1` | none | `ZIL-PARSE-SUMMARY/1` |
| `expand` | `expand-v1` | none | expanded ZIL source |
| `query` | `query-v1` | query name | query witness report |
| `authorize` | `authorization-v1` | object, relation, subject | `ZIL-AUTHORIZATION/1` |
| `impact` | `impact-v1` | changed node | `ZIL-CHANGE-IMPACT/1` |
| `recovery-audit` | `recovery-audit-v1` | request node | `ZIL-RECOVERY-AUDIT/1` |

Unknown operations, wrong arity, missing capabilities, and unsupported protocol versions fail closed.

## Lean worker response

```json
{
  "schema": "ZIL-EXCHANGE/1",
  "request_id": "request:123",
  "protocol_version": 1,
  "operation": "authorize",
  "status": "ok",
  "authority": "lean",
  "assurance": "validated",
  "input_sha256": "sha256:...",
  "result_sha256": "",
  "payload": "ZIL-AUTHORIZATION\t1\n...",
  "errors": [],
  "warnings": ["result-sha256-pending-client-attestation"]
}
```

The Lean worker owns `status`, `authority`, `assurance`, `payload`, and semantic errors. It emits deterministic payload bytes.

Version 1 intentionally assigns transport SHA-256 to the Clojure client. The client computes SHA-256 over the exact UTF-8 payload and replaces the empty `result_sha256` field. It must not modify `authority`, `assurance`, payload bytes, or semantic errors.

## Status

- `ok`: the operation was evaluated successfully. The payload may contain allow, deny, safe, unsafe, known, or unknown as a semantic result.
- `invalid`: request schema, capability, arity, or input was invalid.
- `unsupported`: operation or protocol version was unsupported.
- `error`: the authoritative operation failed during evaluation.
- `transport-error`: reserved for the Clojure client when no valid worker response was obtained.

Semantic denial and unsafe recovery are not transport failures.

## Determinism

For fixed input bytes, arguments, capability set, Lean environment, and repository revision:

- the Lean payload is deterministic;
- errors and warnings are ordered;
- no timestamp or process ID appears in canonical payloads;
- the Clojure result digest is `sha256(exact payload UTF-8 bytes)`.

## Process modes

```bash
lake exe zilWorker -- --stdio
lake exe zilWorker -- --once
```

`--stdio` processes lines until EOF. `--once` reads one line, writes one response, and exits.

## Trust boundary

The client attests byte identity and supervises the process. Lean remains the semantic authority. Neither transport success nor a SHA-256 digest promotes an external claim to Lean kernel evidence.
