# Provenance and impact mainline integration

This branch carries native derivation provenance and change-impact analysis onto the default branch after PR #59 was merged through its feature base rather than directly into `main`.

Included capabilities:

- deterministic per-fact provenance with query and authorization witnesses;
- provenance-backed dependency graph extraction;
- bounded reverse change-impact paths with cycle reporting.

The feature implementations are unchanged. This file records the default-branch ancestry repair.
