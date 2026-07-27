# Native declaration lowering v0.1

## Supported kinds

A conforming native frontend accepts the declaration keywords already recognized
by the Clojure runtime:

```text
SERVICE HOST DATASOURCE METRIC POLICY EVENT PROVIDER
TM_ATOM LTS_ATOM REFINES CORRESPONDS PROOF_OBLIGATION
FORMALIZATION_TARGET LANGUAGE_PROFILE GRAMMAR_PROFILE
PARSER_ADAPTER DSL_PROFILE QUERY_PACK
```

## Processing order

1. expand source macros;
2. parse declaration values;
3. validate each declaration locally;
4. validate the declaration collection globally;
5. lower valid declarations to canonical relations;
6. combine those facts with tuple facts before rule and query execution.

## Identity

An unqualified declaration name receives its kind prefix:

```text
SERVICE api      -> service.api
METRIC latency   -> metric.latency
TM_ATOM parity   -> tm_atom.parity
```

A qualified name remains unchanged.

## Required fields and enums

Required fields and allowed enum values match `src/zil/lower.clj`. Unknown
non-enum attributes remain available for domain-specific data.

## Special lowering

Service dependencies emit direct, inverse, and `dependsOn` relations. Provider
bindings emit `providesFor` inverses. TM and LTS transition maps emit indexed
relation facts with structured transition attributes.

## Rejection

A declaration program is rejected for duplicate identities, missing required
fields, invalid enum values, variables in declaration values, malformed TM/LTS
structures, missing typed references, or service dependency cycles.

## Semantic boundary

Declarations are source conveniences. Their truth conditions are the canonical
relations produced by deterministic lowering. Rule evaluation and queries operate
on those lowered relations through the ordinary native engine.
