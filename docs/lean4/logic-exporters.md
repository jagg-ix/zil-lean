# Logic exporters

Canonical ZIL facts and Horn rules can be exported directly from Lean to Soufflé Datalog or Prolog.

```lean
let program := Zil.Export.exportProgram .souffle facts rules
let prolog := Zil.Export.exportProgram .prolog facts rules
```

For persistent environment state:

```lean
#zil_export_souffle
#zil_export_prolog
```

The exporter:

- sanitizes relation names into deterministic predicates;
- emits ground nodes as quoted atoms;
- emits variables with a `V_` prefix;
- emits Soufflé `.decl` rows with two symbol columns;
- preserves premise order and rule direction;
- never changes trust classification.

This provides the external query/reasoning adapter from the original architecture. Exported programs may be consumed by Soufflé, Prolog tooling, or downstream analysis pipelines.

Lean remains pinned to `leanprover/lean4:v4.31.0`.