# Public content policy

This repository is for the ZIL language, implementation, specifications, examples,
and operational tooling that are intended for public use.

Do not commit:

- personal names, personal email addresses, phone numbers, or home addresses unless
  publication is deliberate and documented;
- absolute workstation paths such as user home directories;
- credentials, private keys, access tokens, cookies, or environment files;
- URLs or coordinates for private repositories;
- unpublished research notes, experimental results, theorem campaigns, private branch
  names, private commit identifiers, or project-specific research roadmaps;
- generated files whose headers retain a developer's local source path.

Public examples should use synthetic project names, neutral requirements, and placeholder
identities. Generated artifacts should record repository-relative source paths.

Run the tracked-content audit before publishing:

```bash
bash scripts/public-content-audit.sh
```

The automated audit detects common disclosure classes. It cannot determine whether a
technical document exposes unpublished research. That remains a required human review.

Removing a file in a new commit removes it from the current tree, not from existing Git
history, forks, caches, release archives, or previously published package artifacts. A
history rewrite and coordinated cache/release cleanup are separate operations when past
content must also become inaccessible through normal repository history.
