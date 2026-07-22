# Formalization coverage linter

The linter evaluates the closed persistent knowledge graph and reports gaps that can cause a formalization agent to silently lose requirements or evidence.

## Commands

Report issues as warnings:

```lean
#zil_lint
```

Fail elaboration when any issue remains:

```lean
#zil_lint!
```

The strict form is intended for selected CI-facing aggregation modules after the underlying declarations, facts, rules, and evidence have been imported.

## Diagnostics

### `unsupportedClaim`

A declaration formalizes a claim, but the claim has no `zil.supportedBy` relation.

### `unpropagatedRequirement`

A declaration formalizes a claim and requires a requirement, but closure does not contain:

```text
claim zil.requiresClaim requirement
```

This catches missing or unregistered requirement-propagation rules.

### `unlinkedDeclaration`

A declaration occurs as the subject of `zil.formalizes`, but no `zil_link` metadata entry connects the graph relation to a Lean declaration.

### `linkedWithoutClaim`

A declaration has `zil_link` metadata but no `zil.formalizes` relation in the closed graph.

## API

```lean
let issues := Zil.Lint.scan env
let isClean := Zil.Lint.clean env
let message := Zil.Lint.render issue
```

`scan` uses the bounded Horn closure engine, so requirements satisfied by registered graph rules are recognized.

## Identifier handling

Declaration coverage is matched through the canonical subject stored in the linked relation. The linter does not guess conversions between Lean declaration names and graph node prefixes such as `lean.*`.

## Trust boundary

The linter checks metadata completeness and graph consequences. It does not claim that evidence is scientifically sufficient or that a Lean declaration proves a claim merely because a `formalizes` edge exists.

## Validation

```bash
lake build
lake exe zilLeanTests
```

Fixtures include one clean formalization and one intentionally incomplete formalization that must produce unsupported-claim, unlinked-declaration, and unpropagated-requirement diagnostics.
