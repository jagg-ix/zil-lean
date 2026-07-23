# Native proof-obligation governance

`PROOF_OBLIGATION` declarations can now be audited by the native Lean frontend without treating an unavailable external backend as a successful skip.

## Command

```bash
bin/zil proof-obligations \
  examples/proof-obligations/governance.zc
```

Filter by one backend:

```bash
bin/zil proof-obligations \
  examples/proof-obligations/governance.zc \
  lean4 \
  /tmp/lean-obligations.txt
```

Accepted filters are:

```text
all
-
z3
tlaps
lean4
acl2
manual
```

## Governance rather than solver execution

The native command validates declaration state and evidence. It does not execute Z3, TLAPS, ACL2, or an arbitrary shell command from inside Lean.

The original Clojure bridge remains available for backend execution. Its result or artifact can be referenced by the native declaration and then audited as evidence.

Only `lean4` is classified as a native backend. This classification does not automatically discharge an obligation: a `proved` status still requires an explicit proof token, declaration reference, or other evidence reference.

## Verdicts

```text
satisfied
violated
blocked
waived
```

Rules:

- `failed` is violated;
- `open` and `pending` are blocked;
- external open/pending obligations without evidence explicitly report `backend-unavailable-without-evidence`;
- `proved` is satisfied only when evidence is present;
- `waived` requires a nonempty `waiver_reason`;
- critical obligations cannot be waived;
- an obligation whose relation is unknown in facts and rule conclusions is blocked.

The audit passes only when no selected obligation is violated or blocked.

## Evidence references

Evidence is collected from these declaration attributes:

```text
evidence
artifact_in
artifact_out
proof_token
declaration
```

These are references, not proof verification performed by this command. The referenced artifact or declaration should be checked by its appropriate producer before the obligation status is set to `proved`.

## Report

`ZIL-PROOF-OBLIGATIONS/1` records:

- module and optional tool filter;
- aggregate counts;
- relation, tool, status, and criticality;
- native or external backend classification;
- evidence references;
- fail-closed reasons;
- original statement.

## Exit status

```text
0 no violated or blocked obligations
1 governance failure or evaluation error
2 invalid command shape
```

An empty selected obligation set passes. Use repository policy or a higher-level release gate when at least one obligation must exist.

## Trust boundary

A satisfied native governance row means the declaration is internally consistent and carries evidence. It does not independently replay an external solver, prove an empirical claim, or construct a Lean proof term.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil proof-obligations examples/proof-obligations/governance.zc
```
