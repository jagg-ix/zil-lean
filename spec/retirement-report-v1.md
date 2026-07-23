# ZIL legacy retirement report v1

## Inputs

The guard consumes:

1. `ZIL-PORT-GATE/1`;
2. `ZIL-LEAN-VERIFY/1`;
3. `ZIL-EMBEDDED-MANIFEST/1`;
4. an EDN component policy.

All report schemas are checked before repository scanning begins. The policy must exist and define at least one component with at least one consumer pattern.

## Consumer scan

The policy selects repository roots and text patterns. Every match records:

```clojure
{:component :legacy-public-cli
 :pattern :clojure-main
 :path "src/example.clj"
 :line 8
 :text "[zil.cli :as legacy]"
 :allowed false
 :non-blocking false
 :blocking true}
```

Exact allowed paths and allowed prefixes identify files owned by the component. Configured documentation, test, and example prefixes remain visible in the inventory but do not block retirement.

Extensionless wrappers are scanned regardless of executable-mode metadata. A configured scan root that does not exist is an error.

## Evidence checks

A component may require:

```text
port-gate global success
selected port-gate components marked retirable
generated-module verification success
aggregate import status :verified
embedded compilation success
minimum embedded block count
all embedded generated modules verified
```

When `:require-embedded-verification true`, the embedded report must satisfy:

```text
:verify-generated true
:verified == :block-count
```

Otherwise the component receives:

```clojure
{:kind :embedded-modules-not-verified
 :verify-generated false
 :verified 0
 :blocks 12}
```

## States

```text
:active           required evidence is incomplete
:frozen           evidence is complete and blocking consumers remain
:ready-to-remove  evidence is complete and no blocking consumer remains
```

## Output

```clojure
{:schema "ZIL-RETIREMENT/1"
 :ok true
 :repository-root "/absolute/repository"
 :scanned-files 214
 :ready-to-remove [:legacy-public-cli]
 :active []
 :components
 {:legacy-public-cli
  {:state :ready-to-remove
   :evidence-ok true
   :evidence-failures []
   :consumer-count 12
   :blocking-consumer-count 0
   :consumers [...]}}
 :failures []}
```

`:ok` is false when an evidence-complete component has a blocking production consumer.

With `--require-ready`, `:ok` is also false for every configured component whose state is not `:ready-to-remove`.

## Command routing

`bin/zil` recognizes the native commands:

```text
compile
expand
conformance
revision-summary
snapshot
causal-check
```

Other commands require one of:

```text
bin/zil --legacy ...
bin/zil-legacy ...
ZIL_LEGACY_MODE=allow bin/zil ...
```

The native-first wrapper retains the legacy executable and jar build behind the explicit compatibility path.
