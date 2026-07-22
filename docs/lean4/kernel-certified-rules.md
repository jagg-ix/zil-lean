# Kernel-certified rule boundary

Ordinary ZIL rules remain graph metadata and default to `.graphDerived`. A rule may be exposed as `.certified` only through `Zil.Trust.CertifiedRule`, which stores both a Lean proposition and its kernel-checked proof.

```lean
private theorem certificate : True := True.intro

private def certified : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certified
```

`zil_register_graph_rule` rejects rules that manually claim `.certified`. Certified wrappers persist through a separate environment extension and can be projected into inference rules without converting derived graph facts into Lean proof terms.

Lean remains pinned to `leanprover/lean4:v4.31.0`.
