# Differential runtime conformance

The differential harness executes the same `.zc` source through two independent
implementations:

1. the existing Clojure parser, validator, evaluator, and DataScript query path;
2. the native Lean parser, declaration lowering, stratified engine, and query solver.

It compares normalized semantics rather than generated Lean source formatting.

```bash
clojure -M:conformance \
  --root lib \
  --root libsets \
  --root examples \
  --output generated/zil/conformance.edn
```

The convenience command is:

```bash
bin/zil-conformance --root lib --root libsets --root examples
```

## Native semantic report

The Lean CLI exposes one report directly:

```bash
lake exe zil -- conformance examples/conformance/access.zc
```

The output uses `ZILC/1`. Its rows cover:

- module identity;
- declaration identities;
- lowered base facts;
- normalized single-head rules;
- closed facts after stratified evaluation;
- query definitions;
- projected query rows.

Native reports also contain tuple and macro records. The default cross-runtime
comparison treats macro-expanded source as a separate equality check and compares
the shared semantic sections listed above.

## Normalization

The harness normalizes:

- tuple and relation name separators;
- snake-case and camel-case relation aliases;
- numeric user identifiers;
- attribute map ordering;
- rule body ordering;
- rule variable declaration ordering;
- multi-head Clojure rules into one semantic row per head;
- Zanzibar-style usersets into their stored fact and traversal rule.

Query projection order remains significant because it determines row column
meaning.

## Result states

Each source receives one status:

- `:pass` — compared sections and macro expansion match;
- `:mismatch` — both runtimes accepted the source but results differ;
- `:both-rejected` — both frontends rejected the source;
- `:legacy-rejected` — only Clojure rejected it;
- `:native-rejected` — only Lean rejected it.

Shared rejection is accepted as parity. The detailed diagnostic text from both
runtimes is retained for later error-class comparison.

## Section-level differences

Mismatches are grouped by report section. Each section records:

```clojure
{:legacy-only [...]
 :native-only [...]}
```

This makes it possible to distinguish a parser/lowering mismatch from closure or
query-result differences.

## Corpus report

The default report is:

```text
generated/zil/conformance.edn
```

It contains:

```clojure
{:schema "ZIL-CONFORMANCE/1"
 :roots [...]
 :sections [...]
 :ok true
 :entries [...]}
```

Every entry includes the source SHA-256, status, selected sections, differences,
and macro-expansion equality.

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
clojure -M:conformance --root examples/conformance
```
