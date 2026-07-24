# Runtime architecture evaluation v1

## Purpose

`ZIL-RUNTIME-EVALUATION/1` evaluates whether a component is best retained in Lean, Clojure, or a deliberate hybrid arrangement. It does not assume that either language should be removed.

The evaluator is advisory. It never changes code, capability ownership, manifests, or runtime routing automatically.

## Candidates

```text
lean
clojure
hybrid
```

A component declares its current placement, eligible candidates, description, and hard constraints.

Hard constraints may include:

- `requires-kernel-evidence`;
- `requires-dynamic-plugins`;
- `requires-lean-only-profile`.

A Clojure-only candidate is ineligible when kernel evidence or a Lean-only deployment profile is required. A Lean-only candidate is ineligible when dynamic runtime plugins are required. Hybrid candidates remain eligible when they preserve the required authority.

## Metrics

Every candidate is evaluated on normalized values in `[0,1]`:

```text
correctness
latency
throughput
maintenance
extensibility
proof-coverage
reliability
deployment-simplicity
```

Higher is better for every metric. Raw measurements must be transformed into a documented normalized value before ingestion.

Each measurement contains:

```clojure
{:component :component-id
 :candidate :lean
 :metric :correctness
 :value 0.95
 :confidence 0.90
 :samples 20
 :source "benchmark-or-audit-id"}
```

`confidence` is also in `[0,1]`. `samples` is a positive integer. `source` is required so results remain traceable.

## Aggregation

Measurements for one component, candidate, and metric use a confidence-times-sample weighted mean.

A metric is accepted only when it meets the configured minimum confidence and sample count. Candidate score is the weighted mean over accepted metrics, renormalized by the weight actually covered.

The default metric weights are:

```text
correctness           0.20
latency               0.10
throughput            0.10
maintenance           0.15
extensibility         0.15
proof-coverage        0.15
reliability           0.10
deployment-simplicity 0.05
```

The weights sum to `1.0`.

## Decision policy

Default policy:

```clojure
{:minimum-metrics 6
 :minimum-confidence 0.60
 :minimum-samples 1
 :decision-margin 0.05}
```

Outcomes:

- `insufficient-evidence`: no eligible candidate covers enough accepted metrics;
- `review-required`: the leading candidates are closer than the decision margin;
- `retain-current`: the current placement is the sufficiently supported leader;
- `candidate-change`: another placement leads by the required margin.

`candidate-change` always includes `requires-human-approval=true`. It is not an automated migration instruction.

## Report

`ZIL-ARCHITECTURE-EVALUATION/1` records:

- model schema;
- policy and weights;
- measurement count;
- per-component candidate eligibility;
- accepted and rejected measurements;
- normalized scores;
- recommendation and margin;
- aggregate outcome counts.

With no measurements, every component is `insufficient-evidence`.

## Current inventory

`architecture/runtime-evaluation.edn` covers:

- semantic kernel;
- workspace and corpus tooling;
- exchange supervision;
- durable event storage;
- extension registry;
- macro workflow;
- agent mutation workflow;
- external tooling;
- release evidence.

The current placements are inputs to evaluation, not permanent conclusions.

## Measurement guidance

Recommended sources include:

- conformance mismatch counts;
- parser and compiler defect reports;
- median and tail latency;
- sustained throughput;
- process restart and transaction conflict rates;
- code ownership and change-frequency data;
- extension implementation effort;
- proof and theorem coverage;
- installation dependency count;
- reproducibility and deployment failure rates.

Synthetic or estimated values must be labeled clearly in `source` and should use reduced confidence.

## Governance

A runtime-placement change should require:

1. a versioned evaluation report;
2. source measurements;
3. review of hard authority constraints;
4. explicit human approval;
5. a migration plan and compatibility policy;
6. conformance evidence after implementation.

The evaluator is intended to prevent language decisions based on preference alone.
