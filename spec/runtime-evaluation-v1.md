# Runtime placement evaluation v1

## Purpose

`ZIL-RUNTIME-EVALUATION/1` scores where each component of a system is best implemented from measurements, and recommends
keeping or changing its placement. It is advisory: it never changes code, ownership, manifests or routing. `zilEvaluate`
reads a model and measurements (JSON, or EDN when the file name ends in `.edn`) and writes a `ZIL-ARCHITECTURE-EVALUATION/1`
report. It exits 1 exactly when some component's recommendation is `candidate-change`, 2 for input it cannot use.

## Placements

```text
lean  clojure  hybrid
```

A component declares its current placement, its eligible candidates, a description and hard constraints:
`requires-kernel-evidence`, `requires-dynamic-plugins`, `requires-lean-only-profile`. A `clojure` candidate is ineligible when
kernel evidence or a Lean-only profile is required; a `lean` candidate is ineligible when dynamic plugins are required;
`hybrid` stays eligible when it keeps the required authority. The names are data about where a component could live; no
placement makes the tool depend on anything.

## Metrics

Normalized values in `[0, 1]`, higher is better: `correctness latency throughput maintenance extensibility proof-coverage
reliability deployment-simplicity`. A measurement is `{component, candidate, metric, value, confidence, samples, source}`:
`confidence` in `[0, 1]`, `samples` a positive integer, `source` required so results stay traceable.

## Aggregation

Measurements of one component, candidate and metric are averaged with weight confidence × samples. A metric is accepted only
when it meets the minimum confidence and sample count. A candidate's score is the weighted mean over accepted metrics,
renormalized by the weight covered. Default weights (sum 1): correctness 0.20, latency 0.10, throughput 0.10, maintenance
0.15, extensibility 0.15, proof-coverage 0.15, reliability 0.10, deployment-simplicity 0.05.

All arithmetic is exact: the decimals of the model and the measurements are read as rational numbers, so a decision margin is
never decided by rounding. Scores in the report are decimals; the comparison uses the exact values.

## Decision policy

Default `{minimum-metrics: 6, minimum-confidence: 0.60, minimum-samples: 1, decision-margin: 0.05}`, overridable in the model.

- `insufficient-evidence`: no eligible candidate covers enough accepted metrics;
- `review-required`: the leading candidates are closer than the margin;
- `retain-current`: the current placement is the sufficiently supported leader;
- `candidate-change`: another placement leads by the margin; it always carries `requires-human-approval=true`.

With no measurements every component is `insufficient-evidence`.

## Report

Records the model schema, policy and weights, the measurement count, per-component eligibility, accepted and rejected
measurements, scores, recommendation and margin, and outcome counts.

## Governance

A placement change should have a versioned report, its source measurements, review of hard authority constraints, explicit
human approval, a migration plan, and conformance evidence after the change. Synthetic or estimated values must say so in
`source` and use reduced confidence.
