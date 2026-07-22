# Canonical text codec

`Zil.Codec` emits deterministic text for canonical relations and Horn rules. The format preserves names, variables, relation ordering, conclusions, and trust class while deliberately excluding provenance from semantic equality.

```lean
let text := Zil.Codec.encodeRule rule
let decoded := Zil.Codec.decodeRule text
#guard Zil.Codec.ruleRoundTrips rule
```

Malformed terms, relation rows, duplicate conclusions, missing conclusions, and unknown trust classes return `Except.error`.

This provides the parse-normalize-emit-parse boundary required for adapters. Lean remains pinned to `leanprover/lean4:v4.31.0`.
