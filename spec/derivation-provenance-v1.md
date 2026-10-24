# ZIL native derivation provenance v1

## Trace construction

Given validated base facts and safe stratified rules, the provenance engine computes the same stratified closure as the native query engine while retaining one origin for each semantic fact.

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

Each stratum is closed in rounds, and a round that derives no new fact ends it; what a successful run returns is the least fixpoint of section 6.5 of `spec/zil-formal-core-v0.1.md`. The supplied per-stratum `fuel` is only a limit on the number of rounds. It defaults to `Zil.Engine.defaultFuel` (one million), which no program that has a closure comes near, because every round that does not end the stratum adds a fact.

If the rounds run out before a stratum reaches its fixpoint, no trace is returned. The computation fails with `closure did not reach its fixpoint in stratum N within F rounds`, and so does every report built on it (provenance, query explanations, authorization, impact, query governance, agent context). The round that finds nothing new counts toward the limit, so a closure that needs `n` rounds to add its last fact needs a `fuel` of at least `n + 1`.

Until version 4f35b41 of the repository the default was 64 and reaching the bound returned the partial closure without any signal. A rule that extends a path by one step per round (reachability, dependency or access propagation along a chain) then lost every fact beyond the 65th step, and the reports still said they had passed. `Zil.Engine.closure`, which has no way to return an error, still returns the facts derived so far when a `fuel` of the caller's own runs out; `Zil.Engine.closureChecked` is the function that reports it.

The trace is graph-derived evidence. It is not a Lean kernel proof term.
