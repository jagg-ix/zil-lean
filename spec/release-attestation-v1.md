# ZIL release evidence attestation v1

## Request

```json
{
  "format": "zil.release-request.v0.1",
  "release_id": "release:demo-v1",
  "module": "Demo",
  "artifacts": [
    {"path": "workflow/Demo.lean", "sha256": "sha256:..."}
  ],
  "evidence": {
    "workflow": {
      "path": "evidence/workflow.json",
      "artifact": "workflow/Demo.lean",
      "minimum_actions": 1
    },
    "proof_tokens": {"path": "evidence/proof.json"},
    "theorem_locks": {"path": "evidence/locks.json"},
    "authorization": {
      "path": "evidence/authorization.txt",
      "object": "repo.release",
      "relation": "zil.publisher",
      "subject": "agent.release"
    },
    "formalization": {
      "path": "evidence/formalization.txt",
      "required_targets": ["foundations"]
    }
  }
}
```

Artifact paths, evidence paths, and required target IDs are unique. Paths are relative to the request directory and may not escape it.

## Evidence formats

```text
workflow       zil.workflow-verification.v0.1
proof tokens   zil.proof-token-resolution.v0.1
theorem locks  zil.theorem-lock-check.v0.1
authorization  ZIL-AUTHORIZATION/1
formalization  ZIL-FORMALIZATION-PLAN/1
```

All five classes are mandatory.

## Workflow conditions

```text
ok = true
complete = true
module = request.module
verification.status = verified
action_count >= minimum_actions
output_sha256 is present
output_sha256 = actual SHA-256 of workflow.artifact
```

The workflow artifact must appear in the request's artifact list.

## Proof-token conditions

```text
ok = true
module = request.module
token_count > 0
number of resolution rows = token_count
resolved = token_count
unresolved = 0
every row status = resolved
token IDs are unique
event and token batch fingerprints are present
```

## Theorem-lock conditions

```text
ok = true
module = request.module
lock_count > 0
changed = 0
unchanged = lock_count
number of unchanged rows = unchanged
every row is unchanged or additional_allowed
token IDs are unique
lock document fingerprint is present
```

The current event and token batch fingerprints must equal the corresponding proof-token resolution fingerprints.

## Authorization conditions

```text
decision = allow
source = direct or derived
object = request expectation
relation = request expectation
subject = request expectation
```

## Formalization conditions

Every required target exists exactly once and has one of:

```text
verified
reviewed
proved
```

## Attestation

```json
{
  "format": "zil.release-attestation.v0.1",
  "ok": true,
  "release_id": "release:demo-v1",
  "module": "Demo",
  "request_fingerprint": "sha256:...",
  "artifacts": [
    {
      "path": "workflow/Demo.lean",
      "expected_sha256": "sha256:...",
      "actual_sha256": "sha256:...",
      "status": "verified"
    }
  ],
  "evidence": [
    {
      "kind": "workflow",
      "path": "evidence/workflow.json",
      "sha256": "sha256:...",
      "status": "verified",
      "details": {}
    }
  ],
  "failures": [],
  "attestation_fingerprint": "sha256:..."
}
```

`request_fingerprint` covers canonical request JSON. `attestation_fingerprint` covers the canonical attestation body excluding that field. The document has no timestamp.

## Exit status

```text
0 attestation ok
1 evidence or artifact failure
2 invalid request, path, or evidence syntax
```

## Trust boundary

The attestation covers configured repository evidence and internal consistency. It does not prove an external scientific or empirical claim.
