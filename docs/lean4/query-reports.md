# Enriched query reports

`Zil.Engine.reportQuery` and `reportCheck` wrap graph evaluation with the metadata required by the Lean-native acceptance contract.

Reports include:

- result bindings or a Boolean result;
- the closed fact set;
- the current knowledge revision;
- active profile name and version;
- completeness (`complete` or `fuelExhausted`);
- graph derivation metadata and trust class when a registered rule matches the derived relation.

The revision is the size of the persistent knowledge environment. It is intended as an optimistic concurrency token, not a cryptographic digest.

Derivations remain graph metadata. They never become Lean proof terms and preserve the rule's trust class.

```lean
run_cmd do
  let env ← getEnv
  let report := Zil.Engine.reportCheck env target
  logInfo m!"revision: {report.meta.knowledgeRevision}"
```

The established toolchain remains `leanprover/lean4:v4.31.0`.
