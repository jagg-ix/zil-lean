# ZIL native agent context v1

## Request

```lean
structure Request where
  taskId : String
  agentId : String
  scope : String
  changedNodes : Array Name
  requestedQueries : Array Name
  requestedTargets : Array Name
```

Task, agent, and scope are nonempty. At least one changed node is required.

## Construction

1. Validate the complete native program.
2. Compute checked derivation provenance.
3. Extract the default dependency graph.
4. Compute reverse impact for each changed node.
5. Select facts whose subject or object is a changed or affected node.
6. Collect rule names from relevant derived fact origins.
7. Validate explicit query and formalization-target selections, or select them automatically.

## Automatic query selection

A query is selected when any positive or negative premise relation appears among relevant facts.

## Automatic target selection

A target is selected when a changed or affected node token occurs in the target ID, module, file, or declaration.

## Completeness

The bundle is incomplete when:

```text
one or more changed nodes are absent from the dependency graph
an explicitly requested query is missing
an explicitly requested formalization target is missing
```

Issues use:

```text
unknown-changed-node:<name>
missing-query:<name>
missing-formalization-target:<name>
```

## Report

```text
ZIL-AGENT-CONTEXT\t1
status\t<complete|incomplete>
task\t<task ID>
agent\t<agent ID>
scope\t<scope>
module\t<module>
changed\t<names>
unknown-changed\t<names>
affected\t<names>
cycles\t<names>
fact-ids\t<IDs>
originating-rules\t<names>
selected-queries\t<names>
selected-targets\t<names>
issues\t<issues>
impact\t<changed>\t<affected>\t<distance>\t<path>
fact\t<fact ID>\t<stratum>\t<canonical relation>
query\t<name>\t<selected variables>\t<premise relations>
target\t<id>\t<status>\t<priority>\t<module>\t<file>\t<declaration>\t<dependencies>
```

Lists are deterministic. The document has no timestamp.

## Durable identity

```text
context_bundle_id = sha256(exact report bytes)
```

That value may be supplied to the durable action-token protocol.

## Exit status

```text
0 complete context
1 incomplete context or evaluation error
2 invalid command shape
```

## Trust boundary

The bundle packages declared graph context. It does not prove completeness with respect to undeclared dependencies or convert graph evidence into Lean kernel evidence.
