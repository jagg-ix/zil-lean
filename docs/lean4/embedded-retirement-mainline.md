# Embedded compilation and retirement mainline integration

This integration carries the merged embedded-native compiler and native-first retirement guard onto the default branch after their original pull requests were merged into stacked feature branches.

Included capabilities:

- recursive `@zil` block extraction from Lean, Python, Clojure, Rust, and Markdown;
- native `.zc` compilation and generated Lean elaboration;
- deterministic `ZIL-EMBEDDED-MANIFEST/1` source maps;
- native-first `bin/zil` command routing with an explicit legacy compatibility path;
- evidence-based legacy component classification through `ZIL-RETIREMENT/1`.

The implementation remains unchanged from the reviewed feature branches. This file records only the default-branch integration step.
