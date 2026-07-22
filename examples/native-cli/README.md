# Native Lean CLI example

The snapshot `schwarzschild.zilx` contains two asserted facts and one Horn rule.

Build the Lean package:

```bash
lake build
```

Inspect the snapshot:

```bash
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
```

Expected summary:

```text
schema: 1
revision: 3
profile: Zil.Profile.research
profile-version: 0.1
facts: 2
rules: 1
```

Compute closure:

```bash
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
```

The closure includes the derived fact:

```text
rel	node:claim.schwarzschildMetric	zil.requiresClaim	node:requirement.lorentzianMetric
```

Check entailment directly:

```bash
lake exe zil -- check examples/native-cli/schwarzschild.zilx \
  $'rel\tnode:claim.schwarzschildMetric\tzil.requiresClaim\tnode:requirement.lorentzianMetric'
```

Expected output:

```text
true
```

Run a variable query:

```bash
lake exe zil -- query examples/native-cli/schwarzschild.zilx \
  $'rel\tnode:claim.schwarzschildMetric\tzil.requiresClaim\tvar:requirement'
```

Export the same native state:

```bash
lake exe zil -- export examples/native-cli/schwarzschild.zilx souffle
lake exe zil -- export examples/native-cli/schwarzschild.zilx prolog
```

Start the interactive shell:

```bash
lake exe zil -- repl examples/native-cli/schwarzschild.zilx
```

Example session:

```text
zil> summary
zil> closure
zil> query rel	node:claim.schwarzschildMetric	zil.requiresClaim	var:requirement
zil> export prolog
zil> quit
```
