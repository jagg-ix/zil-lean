# Port coverage and retirement gate

The port gate turns compiler and runtime comparison results into a measurable
decision about legacy component retirement.

It consumes:

```text
generated/zil/manifest.edn
generated/zil/conformance.edn
port-gate.edn
```

and writes:

```text
generated/zil/port-gate.edn
```

## Complete workflow

```bash
clojure -M:library \
  --root lib \
  --root libsets \
  --root examples \
  --check

clojure -M:conformance \
  --root lib \
  --root libsets \
  --root examples

clojure -M:port-gate
```

The convenience command is:

```bash
bin/zil-port-gate
```

The command exits with status 1 when any global or component condition fails.
Input/configuration errors use status 2.

## Global metrics

The gate calculates:

- compilation ratio;
- parity ratio, including shared rejection;
- exact semantic-match ratio;
- native acceptance ratio;
- mismatch count;
- native-only rejection count;
- legacy-only rejection count;
- missing conformance-entry count.

The checked-in policy requires all ratios to equal `1.0` and all failure counts
to equal zero.

## Source feature inventory

Every source in the library manifest is classified for:

```text
facts
attributes
usersets
rules
negation
queries
macros
declarations
tm-atoms
lts-atoms
```

The report records total feature counts and the same compilation/conformance
metrics grouped by source root.

## Component retirement

The retirement matrix currently contains:

| Component | Corpus evidence |
|---|---|
| tuple frontend | facts and usersets |
| attribute frontend | attributed tuples/rules/queries |
| rule/query runtime | rules and queries |
| negation runtime | `NOT` bodies |
| macro frontend | `MACRO` or `USE` |
| declaration lowering | declarations, TM atoms, and LTS atoms |
| library corpus | every source in all selected roots |
| revision/causal core | required Lean modules, tests, and specification files |

A component is marked `:retirable true` only when:

1. its minimum source and feature counts are present;
2. its selected sources satisfy compilation and conformance thresholds;
3. mismatch/rejection limits are respected;
4. all configured evidence files exist.

This status means the configured evidence is complete. Actual deletion of a
legacy component remains a separate, explicit repository change.

## Root requirements

The checked-in policy requires these roots to appear in the compiler manifest:

```text
lib
libsets
examples
```

Paths are canonicalized before comparison.

## Configuration

`port-gate.edn` may override:

```clojure
{:global
 {:min-compile-ratio 1.0
  :min-parity-ratio 1.0
  :min-exact-ratio 1.0
  :min-native-acceptance-ratio 1.0
  :max-mismatch 0
  :max-native-rejected 0
  :max-legacy-rejected 0
  :max-missing-conformance 0}

 :required-roots ["lib" "libsets" "examples"]

 :components
 {:macro-frontend
  {:features #{:macros}
   :min-feature-sources 1
   :min-sources 1}}}
```

Global threshold maps and individual component maps are deep-merged with the
default policy. Vector/scalar fields replace defaults.

## Report interpretation

The report has:

```clojure
{:schema "ZIL-PORT-GATE/1"
 :ok false
 :global {...}
 :features {...}
 :roots {...}
 :components {...}
 :failures [...]
 :records [...]}
```

Every failure contains an explicit kind, actual value, and required or allowed
value. Component failures are nested beneath `:component-not-retirable` entries.

## Validation

```bash
clojure -M:test
clojure -M:port-gate
```
