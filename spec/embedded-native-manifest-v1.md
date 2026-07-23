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

## Deterministic identity

A block identity is based on the selected root label, root-relative host path, and ordinal. The plan rejects duplicate block IDs, generated namespaces, or output paths.

## Output

```clojure
{:schema "ZIL-EMBEDDED-MANIFEST/1"
 :roots ["/absolute/src"]
 :output-root "/absolute/generated/embedded"
 :namespace-prefix "Zil.Embedded"
 :check-only false
 :require-blocks true
 :ok true
 :host-count 4
 :block-count 6
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
 :status :compiled
 :output-sha256 "..."
 :bytes 891}
```

## Entry states

```text
:compiled generated Lean was written atomically
:checked  native compilation succeeded without writing output
:failed   native compilation returned nonzero
```

## Scan errors

Host-level extraction errors are retained as:

```clojure
{:host "/absolute/src/orphan.py"
 :message "Embedded ZIL target=self has no following host declaration"
 :data {...}}
```

## Success

`:ok` is true exactly when:

- no host scan error exists;
- every block is compiled or checked;
- `--require-blocks` is either disabled or at least one block exists.

The manifest contains no timestamp.
