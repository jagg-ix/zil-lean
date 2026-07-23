# Release evidence example

This directory is a complete input bundle for the release attestation command.

```bash
bin/zil-release-attest \
  examples/release-evidence/release-request.json \
  /tmp/release-attestation.json
```

The request binds:

- a hashed generated Lean workflow module;
- a verified workflow report;
- one resolved proof token;
- one unchanged theorem statement lock;
- an allow authorization decision;
- one verified formalization target.

All paths in `release-request.json` are relative to this directory. The artifact hash is checked against the actual `workflow/Demo.lean` bytes, and the workflow report's output hash must match that same artifact.

The evidence files are minimal format fixtures. In a real release, generate them with the corresponding commands rather than editing them manually.
