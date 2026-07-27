# Model Exchange TM Atom Profile v0.1

This document specifies the `tm.det` profile.
Other currently supported profile labels in tooling are `lts` and `constraint`.

## Purpose

Define a formal atomic unit for problem/solution exchange where each unit is a
complete deterministic Turing machine (`TM_ATOM`).

This profile is designed for Git-native collaboration:

- each commit may introduce/update one or more `TM_ATOM` units
- each `TM_ATOM` is self-validating and complete
- CI can verify model consistency on every commit

For stricter "one commit unit = one TM atom file" workflows, use `commit-check`
policy described below.

## Declaration Surface

```zc
TM_ATOM <name> [states=#{...}, alphabet=#{...}, blank=<symbol>, initial=<state>, accept=#{...}, reject=#{...}, transitions={[state symbol] [next-state write-symbol :L|:R|:N], ...}].
```

Current parser constraint: declarations are single-line statements.

## Required Fields

- `states`
- `alphabet`
- `blank`
- `initial`
- `accept`
- `reject`
- `transitions`

## Consistency Rules

1. `initial` must belong to `states`.
2. `accept` and `reject` must be non-empty subsets of `states`.
3. `accept` and `reject` must be disjoint.
4. `blank` must belong to `alphabet`.
5. Transition key must be `[state symbol]`.
6. Transition value must be `[next-state write-symbol move]`.
7. `move` must be one of `:L`, `:R`, `:N`.
8. Transition states/symbols must belong to `states` / `alphabet`.
9. Completeness:
   all pairs `(non-halting-state, symbol)` must have exactly one transition.

Where:

- `halting-states = accept ∪ reject`
- `non-halting-states = states \\ halting-states`

## Lowering

`TM_ATOM name` lowers into canonical facts:

- `tm_atom:name#kind@entity:tm_atom`
- one relation fact per scalar/collection attr
- one `transition` fact per transition entry:

`tm_atom:name#transition@tmtr:<idx> [from_state=..., read_symbol=..., to_state=..., write_symbol=..., move=:L|:R|:N]`

## Bundle Policy

`bundle-check` policy for exchange bundles:

1. all `.zc` files compile
2. at least one `TM_ATOM` declaration exists

## Commit Policy (Strict)

`commit-check` policy for commit-like units:

1. all `.zc` files compile
2. each `.zc` file contains exactly one `TM_ATOM` declaration
3. each `.zc` file contains no non-`TM_ATOM` declarations

This profile supports both multi-unit bundles (`bundle-check`) and strict
commit-unit gating (`commit-check`).
