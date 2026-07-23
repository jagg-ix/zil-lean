# ZIL native derivation provenance v1

## Trace construction

Given validated base facts and safe stratified rules, the provenance engine computes the same bounded stratified closure as the native query engine while retaining one origin for each semantic fact.

## Fact identity

```lean
structure FactNode where
  id : Nat
  fact : RelExpr
  origin : Origin
  stratum : Nat
```

Fact IDs are contiguous from zero and assigned in deterministic insertion order.

Semantic duplicate facts reuse the existing fact node. Source metadata does not create a second fact.

## Origins

```lean
inductive Origin where
  | base
  | rule
      (ruleName : Name)
      (premiseFactIds : Array Nat)
      (negativeChecks : Array RelExpr)
      (binding : Binding)
```

A rule origin is valid only when:

- every positive premise unified with the listed fact ID in premise order;
- every negative premise was instantiated by the binding;
- none of those instantiated negative relations matched the stratum's negative fact set;
- the conclusion was instantiated by the same binding.

## Deterministic first derivation

Rules are evaluated in source order. Witnesses follow premise, current-fact, and binding order. The first derivation that inserts a semantic fact is retained. Alternative derivations are not recorded in v1.

## Query witnesses

```lean
structure QueryWitness where
  query : Name
  selected : Array (Name × Term)
  premiseFactIds : Array Nat
  binding : Binding
```

One witness is emitted for every successful positive-premise binding that passes negative-premise checks. Projected rows are not deduplicated at the witness layer.

## Complete trace report

```text
ZIL-PROVENANCE\t1
facts\t<count>
fact\t<id>\t<stratum>\t<canonical relation>
origin\t<id>\tbase
origin\t<id>\trule\t<rule>\t<premise IDs>\t<negative relations>\t<binding>
```

## Query explanation report

```text
ZIL-QUERY-EXPLANATION\t1
query\t<name>
witnesses\t<count>
witness\t<query>\t<selected binding>\t<premise IDs>\t<complete binding>
-- provenance --
<fact and origin rows>
```

## Fact explanation report

```text
ZIL-FACT-EXPLANATION\t1
decision\t<present|absent>
source\t<base|rule|none>
fact-id\t<id or empty>
target\t<canonical relation>
-- provenance --
<fact and origin rows>
```

## Limits

The closure uses the supplied per-stratum fuel, default 64. Reaching the bound returns the partial bounded closure, matching the existing native engine contract.

The trace is graph-derived evidence. It is not a Lean kernel proof term.
