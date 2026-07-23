# ZIL native change impact v1

## Dependency policy

A dependency relation is interpreted as:

```text
subject = dependent
object = dependency
```

The default relation set is:

```text
zil.dependsOn
zil.uses
zil.requires
zil.validates
zil.implements
zil.formalizes
zil.supports
```

Only ground node-to-node facts are included.

## Edge

```lean
structure Edge where
  dependent : Name
  dependency : Name
  relation : Name
  factId : Nat
```

`factId` references the provenance closure from which the graph was extracted.

Edges are ordered by dependency name, dependent name, relation name, and fact ID. Exact duplicate edges are removed.

## Graph

```lean
structure Graph where
  nodes : Array Name
  edges : Array Edge
```

Nodes are unique and lexically ordered.

## Cycles

A node is cyclic when at least one nonempty outgoing dependency path returns to that node. The cycle report contains every participating node in lexical order.

Cycles are diagnostic and do not invalidate the graph.

## Change impact

Reverse breadth-first search starts at the changed dependency. Each node is visited at most once.

```lean
structure Impact where
  node : Name
  distance : Nat
  path : Array Edge
```

The first discovered path is retained. With deterministic edge ordering, this is a deterministic shortest path.

The changed node is not included in `impacts`.

## Dependency graph report

```text
ZIL-DEPENDENCY-GRAPH\t1
nodes\t<count>
edges\t<count>
cycles\t<comma-separated nodes>
edge\t<dependent>\t<relation>\t<dependency>\t<fact ID>
```

## Change-impact report

```text
ZIL-CHANGE-IMPACT\t1
status\t<known|unknown>
changed\t<node>
cycles\t<comma-separated nodes>
affected\t<count>
impact\t<node>\t<distance>\t<direct|transitive>\t<path>
```

A path encodes each dependent-to-dependency edge and its fact ID in changed-to-affected traversal order.

## Exit status

```text
dependency-graph
  0 graph generated
  1 parse, validation, or closure failure
  2 invalid command form

impact
  0 changed node is known
  1 changed node is unknown or evaluation failed
  2 invalid command form
```

## Scope

The report identifies graph-level downstream review scope. It does not assert that every affected implementation must be modified or that the graph is complete with respect to undeclared dependencies.
