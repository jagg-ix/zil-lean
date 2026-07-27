# Native Lean CLI example

This is an optional companion to the direct Lean examples in
[`../lean/README.md`](../lean/README.md). Every command below is exercised by
`make examples GROUP=native`.

`formalization-claims.zc` is a small formalization-claims graph: a Lean
declaration formalizes a claim and requires a requirement; a rule derives
which requirements each claim rests on.

Expand, trace, and query the model:

```bash
bin/zil expand examples/native-cli/formalization-claims.zc -
bin/zil trace examples/native-cli/formalization-claims.zc -
bin/zil query-ci examples/native-cli/formalization-claims.zc
bin/zil explain-query examples/native-cli/formalization-claims.zc claim_requirements
```

Compile the model to a Lean module and elaborate it through the kernel:

```bash
bin/zil compile examples/native-cli/formalization-claims.zc \
  /tmp/FormalizationClaims.lean Zil.Generated.FormalizationClaims
lake env lean /tmp/FormalizationClaims.lean
```

Inspect a revisioned knowledge log (`../revision/release.zilr`):

```bash
bin/zil revision-summary examples/revision/release.zilr
bin/zil snapshot examples/revision/release.zilr 2 -
bin/zil causal-check examples/revision/release.zilr
```

`revision-summary` reports the module, latest revision, and causal edges;
`snapshot` replays the log up to a revision; `causal-check` validates the
event ordering.

This example is useful after learning the Lean API. It demonstrates that the
same canonical graph can be inspected from the standalone Lean executable.
