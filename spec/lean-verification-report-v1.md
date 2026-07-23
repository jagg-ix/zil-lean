# ZIL generated Lean verification v1

## Input

The verifier consumes one `ZIL-LIBRARY-MANIFEST/1` document.

The manifest must contain:

- a nonempty `:output-root`;
- a nonempty `:entries` vector;
- complete source, output, namespace, hash, and status fields;
- unique output paths;
- unique Lean namespaces.

## Module verification

For each entry with status `:compiled` or `:checked`:

```text
actual SHA-256 == manifest :output-sha256
lake env lean <output> exits 0
```

Entries with other compiler states are not accepted as verified modules.

## Aggregate

The aggregate source is:

```text
sort(unique("import " + entry.namespace))
```

Only compiler entries with `:compiled` or `:checked` status contribute imports.

Aggregate elaboration runs only after every individual module is verified. The generated output root is prepended to `LEAN_PATH`.

## Output

```clojure
{:schema "ZIL-LEAN-VERIFY/1"
 :manifest "/absolute/manifest.edn"
 :output-root "/absolute/generated/zil"
 :ok true
 :verified 12
 :not-verified 0
 :entries
 [{:source "..."
   :output "..."
   :namespace "Zil.Generated.Lib.Access"
   :source-sha256 "..."
   :output-sha256 "..."
   :status :verified}]
 :aggregate
 {:path "/absolute/generated/zil/All.lean"
  :status :verified
  :sha256 "..."
  :imports 12}}
```

The report contains no timestamp.

## Individual states

```text
:verified      hash and elaboration succeeded
:missing       generated file is absent
:hash-mismatch generated content differs from the manifest
:failed        Lean elaboration returned nonzero
:skipped       compiler entry was not compiled or checked
```

## Aggregate states

```text
:verified aggregate elaboration succeeded
:failed   aggregate elaboration returned nonzero
:blocked  at least one individual module was not verified
:skipped  aggregation was disabled or no imports were available
```

## Success

`:ok` is true exactly when:

```text
all individual entries are :verified
and aggregate status is :verified or :skipped
```
