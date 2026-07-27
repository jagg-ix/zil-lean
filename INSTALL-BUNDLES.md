# Source bundles and versioned installation

The setup scripts prepare a repository checkout. This layer makes that checkout
relocatable and supports controlled installation, verification, upgrade, and removal.

## Build a source bundle

Tarball:

```bash
bin/zil package --format tar.gz --output dist
```

or:

```bash
make package
```

Directory bundle for inspection or lifecycle testing:

```bash
bin/zil package --format dir --output dist
```

or:

```bash
make package-dir
```

The packager uses one committed Git ref. Uncommitted working-tree files are excluded.
Each bundle contains:

```text
ZIL-BUNDLE-METADATA.tsv
ZIL-BUNDLE-MANIFEST.tsv
SHA256SUMS
```

`ZIL-BUNDLE-MANIFEST.tsv` records the byte length and SHA-256 of packaged regular
files, excluding the manifest and checksum files themselves. Git symlink modes remain
part of the archive but are not separate v1 manifest rows.

## Install from a checkout

Copied installation:

```bash
bin/zil install \
  --prefix "$HOME/.local" \
  --source . \
  --mode copy \
  --profile full
```

Equivalent Make target:

```bash
make install PREFIX="$HOME/.local" SETUP_PROFILE=full
```

The copied root is installed under:

```text
~/.local/lib/zil-lean/versions/<version>-<source-id>
```

`~/.local/lib/zil-lean/current` points to the active immutable root. The public wrapper
is `~/.local/bin/zil`.

Ensure the prefix bin directory is on `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Install from an extracted bundle

```bash
tar -xzf dist/zil-lean-<version>.tar.gz
cd zil-lean-<version>
bin/zil install --prefix "$HOME/.local" --source . --mode copy --profile full
```

When bundle metadata is present, the installer verifies every regular file listed by
the manifest before it copies or activates the root.

## Development link

A linked installation keeps the active checkout as the runtime root:

```bash
bin/zil install \
  --prefix "$HOME/.local" \
  --source . \
  --mode link \
  --profile full
```

or:

```bash
make install-link PREFIX="$HOME/.local" SETUP_PROFILE=full
```

Uninstall removes the wrapper, current pointer, and installer-owned root metadata, but
never deletes the linked checkout.

## Install without building

Useful for inspecting layout or exercising the installer independently from Lean and
Clojure dependencies:

```bash
bin/zil install \
  --prefix /tmp/zil-prefix \
  --source . \
  --mode copy \
  --profile lean \
  --no-build
```

`--install-tools` delegates to the existing setup bootstrap and may install Elan or
the official Clojure CLI in user space. The installer does not invoke `sudo`.

## Verify an installation

From the source or bundle root:

```bash
bin/zil verify-install --prefix "$HOME/.local" --structural
```

Through the installed wrapper:

```bash
zil verify-install --structural
```

Run the installed smoke profile as well:

```bash
zil verify-install --smoke
```

Structural verification checks executable wrapper ownership, active-root binding,
root version and install ID, bundle file hashes, and the installation-infrastructure
self-check.

## Upgrade

Install a newer bundle or checkout using the same prefix:

```bash
/path/to/new/zil-lean/bin/zil install \
  --prefix "$HOME/.local" \
  --source /path/to/new/zil-lean \
  --mode copy \
  --profile full
```

The candidate is copied and optionally built before `current` changes. Previous roots
remain available until explicitly pruned.

Remove inactive copied roots after successful activation:

```bash
/path/to/new/zil-lean/bin/zil install \
  --prefix "$HOME/.local" \
  --source /path/to/new/zil-lean \
  --mode copy \
  --profile full \
  --prune-old
```

Installing the same version and source identifier again requires `--force`. A forced
installation creates another immutable root rather than deleting the active root
before preparation.

## Uninstall

Through the installed wrapper:

```bash
zil uninstall
```

From a source or bundle root:

```bash
bin/zil uninstall --prefix "$HOME/.local"
```

Normal uninstall removes the active copied root but retains older inactive immutable
roots.

Remove all copied versions explicitly:

```bash
bin/zil uninstall --prefix "$HOME/.local" --purge --force
```

The uninstaller validates every managed path before mutation. It refuses to delete an
unowned launcher, a non-symlink current path, or a copied root outside the managed
versions directory.

## Dependency-light lifecycle test

```bash
bin/zil test-install \
  --report .zil/install-lifecycle-test.tsv
```

or:

```bash
make test-install
```

The lifecycle test creates a temporary directory bundle and prefix, then exercises:

- package creation from committed `HEAD`;
- copied installation with `--no-build`;
- bundle hash and install-ID verification;
- installed-wrapper self-check;
- forced immutable replacement;
- normal uninstall and wrapper/current absence;
- retention of the prior inactive root;
- explicit purge and versions-directory cleanup.

It does not download dependencies, run Lean tests, or run the Clojure suite.

## Reports

```text
ZIL-PACKAGE-REPORT/1
ZIL-INSTALL-REPORT/1
ZIL-INSTALL-VERIFY/1
ZIL-UNINSTALL-REPORT/1
ZIL-INSTALL-LIFECYCLE-TEST/1
```

Reports separate byte/layout validation from semantic validation. Use the normal
`smoke`, `lean`, `clojure`, `hybrid`, `durable`, or `all` profiles for runtime tests.
