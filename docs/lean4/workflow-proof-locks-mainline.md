# Workflow, proof-token, and theorem-lock mainline integration

This integration carries the merged workflow evidence, proof-token resolution, and theorem statement-lock targets onto the default branch after their original pull requests were merged through stacked feature branches.

Included capabilities:

- native `Zil.Workflow` evidence and verified workflow exports;
- proof-token resolution against complete Lean declaration event batches;
- theorem statement locks based on declaration identity and `type_fingerprint`.

The implementation is unchanged from the reviewed feature branches. This file records only the default-branch integration step.
