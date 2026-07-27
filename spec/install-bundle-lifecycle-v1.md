# ZIL source bundle and installation lifecycle v1

## Scope

This specification defines source packaging, versioned installation, activation,
verification, upgrade, and uninstall behavior for ZIL.

It does not change ZIL semantics, Lean proof authority, Clojure operational authority,
or the existing runtime architecture.

## Public commands

```text
bin/zil package
bin/zil install
bin/zil verify-install
bin/zil uninstall
bin/zil test-install
```

The corresponding direct scripts are:

```text
scripts/package.sh
scripts/install.sh
scripts/verify-install.sh
scripts/uninstall.sh
scripts/install-lifecycle-test.sh
```

Make targets are adapters over the same scripts.

## Source bundle

A source bundle is built from one committed Git ref.

```bash
bin/zil package --format tar.gz --output dist
```

Formats:

```text
tar.gz
dir
```

Uncommitted working-tree files MUST NOT be included.

### Bundle metadata

File:

```text
ZIL-BUNDLE-METADATA.tsv
```

Schema:

```text
ZIL-SOURCE-BUNDLE/1
```

Required fields:

```text
name
version
source_ref
source_commit
source_epoch
layout
```

The v1 layout is `source-complete`: it includes the Lean project, Clojure project,
launchers, setup and test scripts, examples, extensions, specifications, and tests.

### File manifest

File:

```text
ZIL-BUNDLE-MANIFEST.tsv
```

Schema:

```text
ZIL-BUNDLE-MANIFEST/1
```

Rows:

```text
path	bytes	sha256
```

The manifest covers regular files. It excludes itself and `SHA256SUMS` to avoid
recursive identities. Git symlink modes remain represented by the Git archive but do
not receive separate v1 manifest rows.

Every listed regular file MUST match both the recorded size and SHA-256 before bundle
installation.

### Package report

Schema:

```text
ZIL-PACKAGE-REPORT/1
```

It records version, source ref, source commit, format, artifact path, artifact digest,
manifest digest, checksum-file digest, and final status.

## Installation layout

Default prefix:

```text
~/.local
```

Managed paths:

```text
PREFIX/bin/zil
PREFIX/lib/zil-lean/current
PREFIX/lib/zil-lean/versions/<version>-<source-id>
PREFIX/share/zil-lean/install.tsv
```

The wrapper schema marker is:

```text
ZIL-INSTALL-WRAPPER/1
```

The active-root metadata marker is:

```text
ZIL-INSTALL-ROOT/1
```

The installation state schema is:

```text
ZIL-INSTALL-STATE/1
```

The state and root metadata include both `version` and `install_id`.

## Installation modes

### Copy

Copy mode installs an immutable root under `versions/`.

The directory name combines:

```text
<version>-<source-id>
```

`source-id` is derived in this order:

1. the source commit from bundle metadata;
2. the Git checkout or worktree commit;
3. the bundle-manifest SHA-256;
4. a SHA-256 fallback over version and `lakefile.lean`.

A repeated installation of the same identifier is rejected unless `--force` is
supplied. A forced repeat creates another immutable identifier. It MUST NOT delete the
active root before candidate preparation succeeds.

### Link

Link mode points `current` at an existing development checkout. The installer MAY run
setup/build in that checkout. Uninstall MUST NOT delete the linked source tree.

Installer-owned `.zil-install.tsv` metadata MAY be removed from a linked source during
uninstall after ownership validation.

## Prefix and launcher safety

A custom installation prefix MUST also be passed to the setup bootstrap so any
user-space Clojure CLI installation and generated environment file refer to the same
prefix.

The installer MUST refuse to replace:

- a non-symlink object at the managed `current` path;
- an existing `PREFIX/bin/zil` that lacks `ZIL-INSTALL-WRAPPER/1`.

## Atomic activation

Candidate preparation occurs before activation.

For copy mode:

1. verify bundle hashes when present;
2. copy source into a temporary managed root;
3. write root metadata;
4. optionally resolve dependencies and build;
5. rename the prepared candidate to its immutable final root;
6. atomically replace the `current` symlink;
7. atomically replace the installer-owned wrapper and state.

A preparation failure MUST leave the prior `current` pointer unchanged.

`--prune-old` MAY remove inactive copied roots only after activation succeeds.

## Installed wrapper

The installed wrapper resolves `PREFIX/lib/zil-lean/current/bin/zil`.

It also handles:

```text
zil verify-install
zil uninstall
```

These management commands receive the wrapper prefix through `ZIL_INSTALL_PREFIX`.
All other commands are delegated to the active root.

## Installation verification

```bash
bin/zil verify-install --prefix PREFIX --structural
```

Schema:

```text
ZIL-INSTALL-VERIFY/1
```

Structural verification checks:

- installation-state schema;
- executable wrapper and ownership marker;
- current-root resolution;
- state/current binding;
- active-root version and install ID;
- active-root launcher;
- every regular file listed by the bundle manifest when present;
- the dependency-light installation infrastructure self-check.

Optional smoke verification:

```bash
bin/zil verify-install --prefix PREFIX --smoke
```

Smoke verification runs the installed `smoke` test profile and preserves its report.

## Uninstall

```bash
bin/zil uninstall --prefix PREFIX
```

Schema:

```text
ZIL-UNINSTALL-REPORT/1
```

All managed paths MUST be validated before any mutation.

Safety rules:

- remove the launcher only when it contains `ZIL-INSTALL-WRAPPER/1`;
- reject a non-symlink object at the managed `current` path;
- remove a copied active root only when it is under the managed versions directory;
- never remove a linked development source tree;
- remove linked-root metadata only after validating `ZIL-INSTALL-ROOT/1`;
- `--purge` removes every copied version but still writes an uninstall report;
- missing state requires explicit `--force`.

Normal uninstall removes the active copied root but retains older inactive copied roots.
Explicit purge removes those inactive roots.

## Lifecycle test

```bash
bin/zil test-install
```

Schema:

```text
ZIL-INSTALL-LIFECYCLE-TEST/1
```

The test MUST use a temporary prefix and `--no-build`. It exercises:

1. directory bundle creation from committed `HEAD`;
2. copied installation;
3. structural verification and bundle hashes;
4. installed-wrapper self-check;
5. forced immutable replacement;
6. normal uninstall;
7. absence of wrapper and current pointer;
8. retention of the prior inactive immutable root;
9. explicit purge;
10. absence or emptiness of the managed versions directory.

The test does not resolve project dependencies or execute Lean/Clojure suites.

## Report separation

Packaging, installation, verification, uninstall, and lifecycle-test reports are
distinct. A passing package report does not imply that an installation builds or that
ZIL semantic tests pass.

## Authority boundary

- Git and the packaging script identify committed source bytes.
- The installer owns filesystem layout, activation, and wrapper state.
- Verification owns byte/layout checks only.
- Lean remains authoritative for semantic and proof results.
- Clojure remains authoritative for operational control-plane decisions and durable
  transactions.
- Bundle hashes do not promote external evidence to Lean proof.
