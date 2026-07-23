# Native derivation provenance

The native engine can now retain the concrete evidence used to derive each fact instead of returning only the final closure.

## Commands

Complete closure trace:

```bash
bin/zil trace examples/provenance/access.zc
```

Explain every witness for one query:

```bash
bin/zil explain-query examples/provenance/access.zc ancestors
```

Explain one exact authorization relation:

```bash
bin/zil explain-authorization \
  examples/provenance/access.zc \
  doc:readme viewer user:11
```

The authorization explanation exits with 0 when the target fact is present and 1 when it is absent.

## Fact nodes

Every closure fact receives a stable numeric ID and one origin:

```text
base
rule
```

A rule origin records:

- the rule name;
- fact IDs that matched its positive premises;
- instantiated negative relations checked absent;
- the complete variable binding;
- the conclusion stratum.

Fact IDs are assigned in deterministic base-fact, stratum, rule, and witness order.

## First-derivation policy

The trace retains the first semantic derivation of each fact. Later derivations of the same semantic relation are ignored.

This policy keeps the closure finite and deterministic. It gives a concrete valid explanation, but it does not enumerate every alternative proof path. A future exhaustive proof-DAG mode can be layered over the same witness engine without changing the current report contract.

## Negation

For a successful stratified-negative rule, the trace records the instantiated negative relations that were checked absent. It does not manufacture a positive fact representing absence.

The negative fact set is frozen at the beginning of each stratum, matching the existing checked stratified closure semantics.

## Query witnesses

A query witness records:

- selected variable values;
- the complete binding;
- fact IDs supporting each positive premise.

Multiple witnesses may project to the same selected row when different premise facts justify it. The command intentionally reports witnesses rather than deduplicated query rows.

## Reports

```text
ZIL-PROVENANCE/1
ZIL-QUERY-EXPLANATION/1
ZIL-FACT-EXPLANATION/1
```

The query and fact explanation reports include the complete fact table, allowing every premise ID to be resolved without consulting another file.

## Native API

```lean
Zil.Engine.Provenance.Origin
Zil.Engine.Provenance.FactNode
Zil.Engine.Provenance.Trace
Zil.Engine.Provenance.traceChecked
Zil.Engine.Provenance.traceProgram
Zil.Engine.Provenance.queryWitnesses
Zil.Engine.Provenance.explainFact
```

## Trust boundary

Provenance proves how the native graph engine obtained a relation under the supplied facts and rules. It does not convert graph-derived relations into Lean kernel theorems or establish an external scientific claim.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil trace examples/provenance/access.zc
bin/zil explain-query examples/provenance/access.zc ancestors
bin/zil explain-authorization examples/provenance/access.zc doc:readme viewer user:11
```
