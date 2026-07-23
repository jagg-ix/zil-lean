# Native agent context bundles

Agent context bundles package the graph evidence needed to continue a task without reconstructing repository state from conversation history.

## Command

```bash
bin/zil agent-context \
  examples/agent-context/project.zc \
  task:parser-change \
  agent:reviewer \
  Zil/Parser \
  lean:Parser.parse
```

Optional comma-separated query and formalization-target selections may follow:

```bash
bin/zil agent-context \
  examples/agent-context/project.zc \
  task:parser-change \
  agent:reviewer \
  Zil/Parser \
  lean:Parser.parse \
  parserDependencies,parserImpact \
  parser_review,proof_review \
  /tmp/parser.context
```

Use `-` for automatic selection or no explicit selection.

## Bundle contents

`ZIL-AGENT-CONTEXT/1` records:

- task, agent, scope, and module;
- changed and unknown changed nodes;
- direct and transitive affected nodes;
- dependency-cycle nodes;
- deterministic shortest impact paths with provenance fact IDs;
- relevant provenance facts;
- rules that originated relevant derived facts;
- selected queries and their premise relations;
- selected formalization targets and dependencies;
- completeness issues.

## Automatic selection

When no query list is supplied, queries are selected when one of their positive or negative premise relations occurs among the relevant facts.

When no formalization-target list is supplied, targets are selected when their ID, module, file, or declaration references a changed or affected node.

Explicit query and target lists are validated. Missing names make the bundle incomplete.

## Completeness

A bundle is complete when:

```text
all changed nodes exist in the dependency graph
all explicitly requested queries exist
all explicitly requested formalization targets exist
```

The command returns exit code 0 for a complete bundle and 1 for an incomplete bundle. Structural parsing or evaluation errors also return 1; invalid command shape returns 2.

## Durable bundle identity

The canonical report contains no timestamp. A durable identifier is:

```text
context_bundle_id = sha256(exact ZIL-AGENT-CONTEXT/1 bytes)
```

The existing action-token workflow already requires `context_bundle_id`. This binds an issued action token to the exact impact, fact, query, and formalization context reviewed before mutation.

## Native API

```lean
Zil.AgentContext.Request
Zil.AgentContext.ImpactEntry
Zil.AgentContext.Bundle
Zil.AgentContext.build
Zil.AgentContext.render
```

## Scope boundary

The bundle is a deterministic graph-derived handoff. It identifies relevant review context but does not assert that every affected file must change, that undeclared dependencies do not exist, or that graph evidence is a Lean kernel theorem.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil agent-context \
  examples/agent-context/project.zc \
  task:parser-change agent:reviewer Zil/Parser lean:Parser.parse
```
