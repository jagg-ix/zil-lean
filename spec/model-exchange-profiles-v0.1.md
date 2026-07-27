# Model Exchange Profiles v0.1

## Layer Separation

This profile spec separates concerns:

1. Core language layer:
- canonical facts/rules/queries/declarations
- parser + lowering + execution semantics

2. Profile layer:
- defines model-unit formalism used in exchange checks
- maps to declaration kind + validation style

3. Policy layer:
- Git/repo gate rules (`bundle-check`, `commit-check`)
- strictness choices (for example unit-only commit files)

## Supported Profiles

### `tm.det`
- unit declaration: `TM_ATOM`
- intended use: complete deterministic machine fragments

### `lts`
- unit declaration: `LTS_ATOM`
- intended use: operational workflows and incident/state progression

### `constraint`
- unit declaration: `POLICY`
- intended use: invariants, guardrails, and consistency conditions
- execution check: SMT-backed (Z3)
- condition syntax: arithmetic/boolean infix expression, e.g. `x > 10 AND y <= 3`
- implication is supported as `IMPLIES`, `->`, or `=>`, e.g. `x > 0 IMPLIES y > 0`

## Bundle Policy

`bundle-check <path> [profile]` enforces:

1. all `.zc` files compile
2. bundle contains at least one declaration for the selected profile unit
3. for `constraint`: each policy condition is SAT and joint condition set is SAT

## Commit Policy

`commit-check <path> [profile]` enforces:

1. all `.zc` files compile
2. each `.zc` file has exactly one declaration for the selected profile unit
3. strict mode (default): files contain only selected profile unit declarations
4. for `constraint`: SMT satisfiability checks must pass

Non-strict mode is supported by API (`strict-units-only? false`) and CLI
(`--allow-mixed`) for mixed files.
