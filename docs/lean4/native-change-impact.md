# Native dependency and change-impact analysis

The native engine can extract a provenance-backed dependency graph and compute deterministic reverse impact from a changed project node.

## Commands

```bash
bin/zil dependency-graph examples/impact/project.zc
bin/zil impact examples/impact/project.zc lean:Parser.parse
```

The impact command exits with 0 when the changed node exists in the dependency graph and 1 when it is unknown.

## Default dependency policy

The following relations are interpreted as:

```text
dependent -> dependency
```

```text
dependsOn
uses
requires
validates
implements
formalizes
supports
```

The API accepts a custom relation policy when another domain uses different dependency vocabulary.

## Provenance binding

The graph is extracted from the checked provenance closure, not only source tuples. Consequently:

- base and rule-derived dependency relations are included;
- every edge retains the provenance fact ID that established it;
- impact paths can be resolved against `ZIL-PROVENANCE/1` evidence.

Only ground node-to-node relations enter the dependency graph.

## Reverse impact

For a changed dependency, breadth-first traversal follows reverse edges to nodes that depend on it.

Each affected node records:

- distance from the changed node;
- direct or transitive classification;
- one deterministic shortest path;
- relation and fact ID for every path edge.

Nodes are visited once. Cycles therefore do not cause unbounded traversal.

## Cycles

The graph report and every impact report list nodes participating in direct or transitive dependency cycles. Cycles are reported but do not prevent impact analysis.

This is deliberate: a cyclic project graph still needs a bounded review set, while the cycle list indicates architecture that may require correction.

## Reports

```text
ZIL-DEPENDENCY-GRAPH/1
ZIL-CHANGE-IMPACT/1
```

Graph edges have this shape:

```text
edge  <dependent>  <relation>  <dependency>  <provenance fact ID>
```

Impact rows contain:

```text
impact  <node>  <distance>  <direct|transitive>  <path>
```

## Native API

```lean
Zil.Impact.Policy
Zil.Impact.Edge
Zil.Impact.Graph
Zil.Impact.fromTrace
Zil.Impact.fromProgram
Zil.Impact.Graph.cyclicNodes
Zil.Impact.analyze
Zil.Impact.renderGraph
Zil.Impact.renderImpact
```

## Agent workflow

An agent receiving a changed declaration can use the impact report to recover downstream review scope without reconstructing repository context from chat history. Provenance fact IDs preserve why each node entered the impact path.

The report determines graph-level review scope. It does not by itself prove that every affected source file must change.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil dependency-graph examples/impact/project.zc
bin/zil impact examples/impact/project.zc lean:Parser.parse
```
