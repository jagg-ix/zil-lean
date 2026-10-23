# Embedded ZIL blocks v1

A host-language source file can carry ZIL facts in its comments, next to the code they describe. `zilEmbedded` reads them
without changing the host file: it renders them as facts (`scan`), records them as a baseline (`snapshot`), reports what
changed against a baseline (`drift-check`), and turns each block into a typechecked Lean module (`compile`).

## Hosts

```text
.lean  .py  .clj .cljs .cljc  .rs  .md
```

The extension (case-insensitive) selects the language: Lean 4, Python, Clojure, Rust, Markdown. A file named directly is
read whatever its extension is (language `unknown`). A directory is searched recursively for files with those extensions,
in the order of their path strings.

## Block

```text
@zil [target=self|<target>]
<statement>
...
@endzil
```

The markers may sit behind any comment opener on their own lines (`//`, `;;`, `#`, `/*`, ` *`). The text of the line
that holds `@zil` after the marker is the only part read; `@endzil` ends the block on a later line. Each line between them
loses one comment opener (`/*`, `*/`, `*`, `//`, `;;`, `#`) and a trailing `*/`, and blank lines are dropped.

**Target.** `target=self` (the default) attaches the block to the first declaration after the block that the host
language declares (Lean: `theorem def opaque axiom inductive structure class abbrev`, qualified by the enclosing
`namespace`; Python: `def class`; Clojure: `defn defn- def defmacro`; Rust: `fn struct enum trait`). A block with no such
declaration after it is refused. Any other value is the target as written; the first declaration, if any, still
supplies `declaration_kind`.

**Context words.** A whole word in a statement is replaced by its value when it is not next to a letter, digit, `_`, `.`,
`:` or `-`: `self` (the target), `file`, `module`, `namespace`, `project`, `revision` (the file's SHA-256),
`declaration_kind`, `source_span`. The words are replaced one after another in that order.

**Macros.** `USE NAME(args).` statements are expanded with the macros of the `lib/*.zc` files in the nearest directory above
the host file that has a `lib/` directory, or of `--lib DIR`/the `lib_dir` argument. Only the macros are used; the other
lines of a library are not part of a block.

**Statement.** After expansion each statement must be one canonical ground fact, `subject#attribute@object.`, with `self`
as a subject standing for the target. Anything else is refused, and so is a block with no statements or no `@endzil`.

## Scan

`scan` writes `MODULE <name>.` (default `embedded.annotations`), then for every block seven facts about its id
(`kind`, `target`, `trust`, `source_hash`, `macro_revision`, `start_line`, `end_line`, all values double-quoted) followed by
its statements. The facts must parse as ZIL, or the scan fails. A block id is `embedded:` and the first 16 hex digits of the
SHA-256 of `<path>:<ordinal>`.

## Snapshot and drift

A snapshot is a JSON object `{format: "zil.embedded-snapshot.v0.1", root, module, blocks}` with the blocks sorted by id.
A block is an object whose keys come in the fixed order

```text
path macro_revision start_line source_hash block_id [declaration_kind] module project language trust target
source_span namespace end_line statements
```

and the file is the JSON text with `/` unescaped, non-ASCII escaped as `\uXXXX`, and one trailing newline. The order is part
of the format: baselines written by the earlier implementation are byte-identical.

`drift-check` scans the sources again and compares by block id: `block_removed`, `block_added`, and for blocks in both
`source_changed` (`source_hash`), `macro_changed` (`macro_revision`), `target_changed` (`target`), `expansion_changed`
(`statements`). The report is `{ok, drift, baseline_format, block_count_before, block_count_after, differences}`; the
command exits 1 when `drift` is true.

## Compile

`compile` plans one module per block, compiles it with the native compiler in the same process, writes the Lean module
under `--out` (atomically), and typechecks it with `lake env lean` unless `--no-verify` or `--check` is given. The module
of a block is `MODULE embedded.block.<id with other characters as _>.` followed by its statements.

The Lean namespace of block *n* of `<root>/a/b.lean` is `<prefix>.<Root>.<A>.<B>.Block<n>` (default prefix `Zil.Embedded`;
every segment is its words capitalised, `Generated` if empty, `N` before a leading digit) and its file is
`<out>/<Root>/<A>/<B>/Block<n>.lean`. A plan with two equal ids, namespaces or output paths is refused.

The manifest is JSON with sorted keys (`--manifest`, default `generated/embedded/manifest.json`):

```json
{"schema": "ZIL-EMBEDDED-MANIFEST/1", "roots": [], "output-root": "", "namespace-prefix": "Zil.Embedded",
 "check-only": false, "verify-generated": true, "require-blocks": false, "ok": true,
 "host-count": 0, "block-count": 0, "verified": 0, "compiled": 0, "checked": 0, "failed": 0,
 "hosts": [], "scan-errors": [], "entries": [], "failures": []}
```

An entry has the block's fields, its host, `output`, `lean-namespace`, `zc-sha256`, `zc-bytes`, and a `status`:

```text
verified             compiled and elaborated
compiled             written, verification disabled
checked              compiled, nothing written
failed               the module did not compile (phase compile)
verification-failed  elaboration failed (phase verify, with exit and error)
```

`ok` is true exactly when no host file failed to scan, no entry failed, and `--require-blocks` is off or at least one block
exists. A host file that cannot be scanned is listed under `scan-errors` and does not stop the others. The manifest holds no
timestamp. The command exits 1 when `ok` is false.

## Differences from the earlier implementation

The manifest is JSON, not EDN; its default name ends in `.json`. A compile failure carries no `command`. The wording of a
macro error is the macro expander's.
