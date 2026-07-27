# ZIL port gate v1

## Inputs

The gate accepts:

1. `ZIL-LIBRARY-MANIFEST/1`;
2. `ZIL-CONFORMANCE/1`;
3. an EDN threshold and retirement-component policy.

Entries are joined by canonical absolute source path. Duplicate conformance paths
are rejected.

## Source record

Each joined source record contains:

```clojure
{:source "/absolute/model.zc"
 :root "/absolute/lib"
 :relative "model.zc"
 :features #{:facts :rules :queries}
 :compile-status :compiled
 :compile-ok true
 :conformance-status :pass
 :parity-ok true
 :exact-ok true
 :native-accepted true
 :conformance-ok true}
```

## Metric definitions

For a source set of size `N`:

```text
compile ratio          = compiled-or-checked / N
parity ratio           = pass-or-both-rejected / N
exact ratio            = pass / N
native acceptance      = pass-or-mismatch-or-legacy-rejected / N
```

Zero-source sets receive ratio `0.0`. Evidence-only components skip ratio checks.

## Feature classes

```text
:facts
:attributes
:usersets
:rules
:negation
:queries
:macros
:declarations
:tm-atoms
:lts-atoms
```

Feature detection is an inventory mechanism. Semantic acceptance remains defined
by native compilation and differential reports.

## Component scope

A component chooses one source scope:

- `:features` — sources using any configured component feature;
- `:all` — the complete joined corpus;
- `:none` — evidence-file checks only.

Every configured feature must independently meet `:min-feature-sources`.

## Threshold failures

The gate reports explicit failures for:

```text
:compile-ratio
:parity-ratio
:exact-ratio
:native-acceptance-ratio
:mismatch
:native-rejected
:legacy-rejected
:missing-conformance
:minimum-sources
:feature-coverage
:missing-evidence-file
:missing-required-root
:component-not-retirable
```

## Output

```clojure
{:schema "ZIL-PORT-GATE/1"
 :ok true
 :global {...}
 :features {...}
 :roots {...}
 :components {...}
 :failures []
 :records [...]}
```

Maps are emitted in deterministic sorted order where identifiers are keys.
No timestamp is included.

## Retirement meaning

`:retirable true` states that the configured compiler, semantic parity, feature,
and file evidence conditions are satisfied. It does not delete code or claim
that runtime consumers have already migrated. Removal requires a separate change.
