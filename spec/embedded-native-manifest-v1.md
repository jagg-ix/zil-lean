# ZIL embedded native manifest v1

## Input hosts

Supported host extensions are:

```text
.lean .py .clj .cljs .cljc .rs .md
```

Only explicitly delimited `@zil` / `@endzil` blocks are extracted.

## Block source

Each block is compiled as an independent `.zc` source unit containing:

1. a deterministic `MODULE` declaration derived from its block ID;
2. the context-substituted and macro-expanded statements from the host block.

The temporary source is removed after native compilation.

## Verification

Unless disabled with `--no-verify`, generated Lean is written atomically and elaborated with `lake env lean`. The generated output root is prepended to `LEAN_PATH`.

Check-only mode compiles the temporary `.zc` unit and hashes generated output without writing or elaborating it.

## Deterministic identity

A block identity is based on the selected root label, root-relative host path, and ordinal. The plan rejects duplicate block IDs, generated namespaces, or output paths.

## Output

```clojure
{:schema "ZIL-EMBEDDED-MANIFEST/1"
 :roots ["/absolute/src"]
 :output-root "/absolute/generated/embedded"
 :namespace-prefix "Zil.Embedded"
 :check-only false
 :verify-generated true
 :require-blocks true
 :ok true
 :host-count 4
 :block-count 6
 :verified 6
 :compiled 0
 :checked 0
 :failed 0
 :hosts [...]
 :scan-errors []
 :entries [...]
 :failures []}
```

## Entry

```clojure
{:block_id "embedded:0123456789abcdef"
 :ordinal 0
 :host "/absolute/src/auth/Policy.lean"
 :root "/absolute/src"
 :relative "auth/Policy.lean"
 :scan-path "Src/auth/Policy.lean"
 :language "lean4"
 :target "lean:Auth.Policy.check"
 :start_line 12
 :end_line 16
 :source_hash "sha256:..."
 :macro_revision "sha256:..."
 :source_span "source_span:Src/auth/Policy.lean:12-16"
 :lean-namespace "Zil.Embedded.Src.Auth.Policy.Block0"
 :output "/absolute/generated/embedded/Src/Auth/Policy/Block0.lean"
 :zc-sha256 "..."
 :zc-bytes 192
 :status :verified
 :output-sha256 "..."
 :bytes 891}
```

## Entry states

```text
:verified             native compilation and Lean elaboration succeeded
:compiled             generated Lean was written with verification disabled
:checked              native compilation succeeded without writing output
:failed               native `.zc` compilation returned nonzero
:verification-failed  generated Lean elaboration returned nonzero
```

Failures include:

```clojure
{:status :verification-failed
 :phase :verify
 :exit 1
 :error "..."
 :command [...]}
```

Source compilation failures use `:phase :compile`.

## Scan errors

Host-level extraction errors are retained as:

```clojure
{:host "/absolute/src/orphan.py"
 :message "Embedded ZIL target=self has no following host declaration"
 :data {...}}
```

## Success

With generated verification enabled, `:ok` is true exactly when:

- no host scan error exists;
- every block is `:verified` or check-only `:checked`;
- `--require-blocks` is either disabled or at least one block exists.

With `--no-verify`, generated entries may use `:compiled`.

The manifest contains no timestamp.
