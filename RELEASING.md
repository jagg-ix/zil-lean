# Publishing ZIL Lean releases

ZIL Lean release files are built from one committed Git tag and attached to the
corresponding entry in the repository's GitHub Releases section.

## Release assets

Each release contains:

```text
zil-lean-<version>.tar.gz
zil-lean-<version>.release.tsv
SHA256SUMS
```

The tarball is produced by the existing source-bundle packager. It contains the
committed repository files together with the bundle metadata, internal manifest,
and internal checksums described in `INSTALL-BUNDLES.md`.

The release manifest records the package version, source ref, source commit,
archive size, and archive SHA-256 digest. The release-level `SHA256SUMS` verifies
both the tarball and the release manifest.

## Build release files locally

Build files from the current commit:

```bash
make release-assets
```

Build files from an existing version tag:

```bash
make release-assets \
  RELEASE_REF=v0.1.0 \
  RELEASE_VERSION=0.1.0
```

The files are written to `dist/` by default. Use another directory with:

```bash
make release-assets RELEASE_OUTPUT=/tmp/zil-release
```

Verify the generated files from their output directory:

```bash
cd dist
sha256sum --check SHA256SUMS
```

On macOS, use the equivalent command:

```bash
shasum -a 256 --check SHA256SUMS
```

The release builder refuses an explicit version that does not match the version
stored in `lakefile.lean` at the selected Git ref.

## Pull-request validation

The `Validate release assets` workflow runs for every pull request and every push
to `main`. It performs a dependency-light release check without publishing:

1. checks the Bash syntax of the packaging scripts;
2. constructs the release candidate from the tested commit;
3. verifies every entry in the release-level `SHA256SUMS`;
4. checks the manifest version and source commit;
5. confirms that a mismatched version is rejected;
6. uploads the candidate files as a seven-day workflow artifact.

This validation does not require Lean or Clojure dependencies because a release
contains the committed source bundle rather than a prebuilt runtime.

## Publish a release

1. Update `lakefile.lean` to the intended version and merge that change.
2. Create a tag whose name is exactly `v<version>`.
3. Push the tag to GitHub.

Example:

```bash
git tag -a v0.1.0 -m "ZIL Lean 0.1.0"
git push origin v0.1.0
```

The `Publish release assets` workflow then:

1. checks out the exact tag;
2. verifies that the tag matches `lakefile.lean`;
3. verifies that the checked-out commit is the tagged commit;
4. builds the release files;
5. verifies `SHA256SUMS`;
6. creates the GitHub Release with generated notes, or replaces the assets when
   the release already exists.

A failed or interrupted publication can be retried from the Actions page with
`workflow_dispatch`. Supply an existing `v<version>` tag. Manual publication does
not allow an arbitrary branch or untagged commit.

## Version and integrity rules

- The tag must use the form `v<version>`.
- The tag version must exactly match `lakefile.lean`.
- The workflow checkout must resolve to the tagged commit.
- Packaging always uses committed files from the selected tag.
- Uncommitted working-tree content is never included.
- Existing release assets are replaced only for the same validated tag.
