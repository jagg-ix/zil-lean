# ZIL conformance report v1

## Native report

A native semantic report starts with:

```text
ZILC<TAB>1
module<TAB><module-name>
```

Remaining rows are lexicographically sorted. Source locations and generated
identifier names do not affect semantic comparison.

Shared row kinds are:

```text
declaration<TAB><kind><TAB><entity>
fact<TAB><escaped-relation>
rule<TAB><variables><TAB><trust><TAB><positive><TAB><negative><TAB><conclusion>
closed<TAB><escaped-relation>
query<TAB><name><TAB><variables><TAB><select><TAB><positive><TAB><negative>
query-row<TAB><query-name><TAB><projected-bindings>
```

Native-only diagnostic row kinds may additionally include:

```text
tuple
macro
macro-emit
expansion
expansion-emit
```

## Relation row

A relation has:

```text
rel<TAB><subject-term><TAB><canonical-relation><TAB><object-term><TAB><attributes>
```

Terms use:

```text
node:<name>
var:<name>
```

Attributes are sorted by key and use the existing canonical attribute value
encoding.

## Rules

Rule names are excluded because multi-head legacy rules and native single-head
normalization can choose different generated names. Variable declaration order
is sorted. Positive and negative relation collections are independently sorted.

## Queries

Declared query variables are sorted. Selected variables preserve source order.
Query rows encode selected bindings in that same order.

## Corpus result

The cross-runtime suite emits EDN:

```clojure
{:schema "ZIL-CONFORMANCE/1"
 :roots [...]
 :sections ["closed" "declaration" "fact" "module" "query" "query-row" "rule"]
 :ok true
 :entries [...]}
```

Each entry contains:

```clojure
{:source "..."
 :source-sha256 "..."
 :status :pass
 :ok true
 :sections [...]
 :differences {}
 :expansion-equal true}
```

## Accepted statuses

- `:pass`
- `:mismatch`
- `:both-rejected`
- `:legacy-rejected`
- `:native-rejected`

## Comparison rule

For every selected section, compare the set of complete canonical rows. A source
passes when all selected sets are equal and macro-expanded source text is equal.
Both-rejected sources also pass parity, while retaining diagnostics.
