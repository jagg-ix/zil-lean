# ZIL library manifest v1

## Header

A manifest is an EDN map with:

```clojure
{:schema "ZIL-LIBRARY-MANIFEST/1"
 :roots [...]
 :output-root "..."
 :namespace-prefix "Zil.Generated"
 :check-only false
 :ok true
 :entries [...]
 :stale-removed [...]}
```

## Entry

Each source entry contains:

```clojure
{:source "/absolute/input.zc"
 :root "/absolute/root"
 :relative "relative/input.zc"
 :output "/absolute/generated/Input.lean"
 :namespace "Zil.Generated.Root.Input"
 :source-sha256 "..."
 :status :compiled
 :output-sha256 "..."
 :bytes 1234}
```

Allowed statuses are:

- `:compiled` — native output was written atomically;
- `:checked` — native output was validated and hashed without writing;
- `:failed` — native compilation returned a nonzero exit code.

A failed entry additionally records `:exit`, `:error`, and `:command`.

## Determinism

Entries are ordered by normalized absolute source path. Namespace and output-path
segments use the same deterministic word normalization. The manifest contains no
wall-clock value.

## Safety

The plan rejects duplicate namespaces and duplicate outputs before execution.
Stale cleanup accepts paths only under `:output-root` and runs only after a fully
successful non-check compilation.
