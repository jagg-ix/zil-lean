# Native Lean CLI example

This is an optional companion to the direct Lean examples in
[`../lean/README.md`](../lean/README.md).

The prepared `schwarzschild.zilx` snapshot can be inspected without writing a
new Lean module:

```bash
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
```

Check the derived requirement:

```bash
lake exe zil -- check examples/native-cli/schwarzschild.zilx \
  $'rel\tnode:claim.schwarzschildMetric\tzil.requiresClaim\tnode:requirement.lorentzianMetric'
```

Query for the requirement variable:

```bash
lake exe zil -- query examples/native-cli/schwarzschild.zilx \
  $'rel\tnode:claim.schwarzschildMetric\tzil.requiresClaim\tvar:requirement'
```

Export the same graph:

```bash
lake exe zil -- export examples/native-cli/schwarzschild.zilx souffle
lake exe zil -- export examples/native-cli/schwarzschild.zilx prolog
```

Start the interactive REPL:

```bash
lake exe zil -- repl examples/native-cli/schwarzschild.zilx
```

This example is useful after learning the Lean API. It demonstrates that the
same canonical graph can be inspected from the standalone Lean executable.
