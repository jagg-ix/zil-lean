# Native-first command boundary and retirement guard

The public `bin/zil` command now routes implemented commands directly to the native Lean executable.

```bash
bin/zil compile model.zc
bin/zil expand model.zc
bin/zil conformance model.zc
bin/zil revision-summary state.zilr
bin/zil snapshot state.zilr 12
bin/zil causal-check state.zilr
```

The existing Clojure integrations remain available through an explicit compatibility command:

```bash
bin/zil --legacy query-plan model.zc
bin/zil-legacy query-plan model.zc
```

A temporary environment escape hatch is also available:

```bash
ZIL_LEGACY_MODE=allow bin/zil query-plan model.zc
```

This makes the default command path unambiguous while retaining access to specialized integrations during migration.

## Retirement evidence

The retirement guard combines four reports:

```text
generated/zil/port-gate.edn
generated/zil/verification.edn
generated/embedded/manifest.edn
legacy-retirement.edn
```

Run it with:

```bash
clojure -M:retirement
```

or:

```bash
bin/zil-retirement
```

For a removal-focused change, require every configured component to be ready:

```bash
clojure -M:retirement --require-ready
```

## Component states

### `:active`

Required compiler, parity, elaboration, aggregate-import, or embedded-block evidence is incomplete. Existing consumers remain allowed while the missing evidence is addressed.

### `:frozen`

The evidence is complete, but an unapproved production consumer still calls the legacy surface. The guard fails and lists each path, line, matching pattern, and source text.

### `:ready-to-remove`

The evidence is complete and only owned implementation files, approved compatibility wrappers, or informational test/documentation references remain.

This state permits a separate removal PR. The guard does not delete source files.

## Checked-in policy

`legacy-retirement.edn` currently covers:

- the public Clojure CLI and standalone jar;
- the original tuple-to-Lean exporter;
- the original embedded scanner commands.

For each component, the policy declares:

- required port-gate components;
- whether generated-module verification is required;
- whether aggregate import verification is required;
- whether native embedded compilation is required;
- minimum embedded block coverage;
- source patterns that identify consumers;
- exact implementation files that remain allowed.

Tests, documentation, and examples are inventoried but do not block a component. New production references outside the allowlist do block it once its evidence is complete.

## Report

The command writes:

```text
generated/zil/retirement.edn
```

The report includes:

- all component states;
- evidence failures;
- every matching consumer;
- blocking-consumer counts;
- components ready for removal;
- active components;
- strict-readiness failures.

## Merge and removal procedure

1. Run the library compiler and conformance harness.
2. Pass the port gate.
3. Verify generated Lean modules and the aggregate import.
4. Compile the selected embedded host roots.
5. Run the retirement guard.
6. Remove one ready component in a separate PR.
7. Update its allowlist and rerun the guard.

## Validation

```bash
clojure -M:test
clojure -M:retirement
```
