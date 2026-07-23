# Release evidence attestations

A release attestation joins the evidence produced by the native and bridge layers into one deterministic, fail-closed report.

## Required evidence

Every request names exactly one file for each class:

```text
workflow verification
proof-token resolution
theorem statement-lock check
authorization decision
formalization plan
```

It also lists one or more release artifacts with expected SHA-256 values.

## Command

```bash
bin/zil-release-attest \
  examples/release-evidence/release-request.json \
  /tmp/release-attestation.json
```

Equivalent invocation:

```bash
clojure -M:release-attest release-request.json attestation.json
```

The command exits with 0 only when the final attestation has `ok=true`.

## Evidence joins

The attestor checks more than each report's top-level result.

### Workflow

- format is `zil.workflow-verification.v0.1`;
- store snapshot is complete;
- generated Lean verification status is `verified`;
- module matches the release module;
- action count meets the configured minimum;
- generated module hash matches the named release artifact.

`bin/zil-workflow` accepts an optional final JSON path and writes this versioned report.

### Proof tokens

- format is `zil.proof-token-resolution.v0.1`;
- every row is present and has `resolved` status;
- token IDs are unique;
- summary counts agree with rows;
- event and token batch fingerprints are present;
- module matches the release module.

### Theorem locks

- format is `zil.theorem-lock-check.v0.1`;
- lock set is nonempty;
- every locked row is unchanged;
- summary counts agree with rows;
- current event/token fingerprints equal the proof-token report fingerprints;
- module matches the release module.

The snapshot equality prevents a successful lock report from being combined with a different proof-token resolution run.

### Authorization

- report header is `ZIL-AUTHORIZATION/1`;
- decision is `allow`;
- source is `direct` or `derived`;
- object, canonical relation, and subject equal the request's expected authorization tuple.

### Formalization

- report header is `ZIL-FORMALIZATION-PLAN/1`;
- target IDs are unique;
- every required target exists;
- each required target is `verified`, `reviewed`, or `proved`.

`implemented` alone does not satisfy release evidence.

## Path and artifact integrity

All evidence and artifact paths are relative to the release-request directory. Absolute paths and paths escaping that directory are rejected.

The attestation records:

- expected and actual artifact hashes;
- SHA-256 for every evidence file;
- canonical request fingerprint;
- canonical final attestation fingerprint;
- detailed failure rows.

The request must use unique artifact paths, unique evidence paths, and unique required formalization target IDs.

## Output

```json
{
  "format": "zil.release-attestation.v0.1",
  "ok": true,
  "release_id": "release:demo-v1",
  "module": "Demo",
  "request_fingerprint": "sha256:...",
  "artifacts": [],
  "evidence": [],
  "failures": [],
  "attestation_fingerprint": "sha256:..."
}
```

The report has no timestamp. Equal inputs produce the same fingerprint.

## Scope

The attestation states that the configured repository evidence was present, internally consistent, and successful. It does not establish the empirical truth, scientific sufficiency, or real-world validity of an external claim.

## Validation

```bash
clojure -M:test
bin/zil-release-attest \
  examples/release-evidence/release-request.json \
  /tmp/release-attestation.json
```
