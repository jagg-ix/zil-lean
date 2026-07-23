# ZIL native theorem and claim audit v1

## Theorem discovery

Theorem nodes satisfy:

```text
<node>#kind@entity:theorem
```

## Theorem contract relations

```text
requiresAssumption
requiresLemma
ensures
criticality
unconditional
proofToken
validatedBy
proves
```

Source spellings with underscores normalize to these canonical relation names.

## Non-vacuity

A theorem is non-vacuous exactly when:

```text
requiresAssumption is nonempty
or requiresLemma is nonempty
or unconditional@value.true is present
```

An unconditional theorem still requires at least one guarantee.

Assumption and lemma references are valid only when their targets declare:

```text
kind@entity.assumption
kind@entity.lemma
```

## Criticality

```text
low
medium
high
critical
```

Missing criticality defaults to `low`.

High and critical theorem contracts require one or more proof-evidence links through `proofToken`, `validatedBy`, or `proves`.

## Theorem issue codes

```text
vacuous-contract
guarantee-missing
missing-assumption:<node>
missing-lemma:<node>
proof-evidence-missing
```

## Claim discovery

Claim nodes satisfy:

```text
<node>#kind@entity:claim
```

Claims use `supportedBy` links.

## Evidence classes

```text
kernel       target kind is theorem or proof
empirical    target kind is experiment, dataset, or measurement
documentary  target kind is document, paper, source, or evidence
graph        target has another declared kind
unknown      target has no declared kind
```

A claim passes only when it has at least one support link, every support target has a declared evidence class, and it does not assert `provedClaim@value.true`.

## Claim issue codes

```text
support-missing
support-kind-missing:<node>
external-claim-proof-boundary
```

## Report

```text
ZIL-THEOREM-AUDIT\t1
status\t<pass|fail>
module\t<module>
theorems\t<count>
claims\t<count>
theorem-failures\t<count>
claim-failures\t<count>
theorem\t<node>\t<pass|fail>\t<criticality>\t<nonvacuous|vacuous>\t<unconditional|conditional>\t<assumptions>\t<lemmas>\t<guarantees>\t<proof evidence>\t<issues>
claim\t<node>\t<pass|fail>\t<asserted-proved|not-proved>\t<node:class supports>\t<issues>
```

## Success

The report passes exactly when every theorem contract and every external claim passes its checks.

An empty theorem and claim set passes.

## Trust boundary

Kernel evidence means a referenced Lean theorem or proof node exists in the project graph. The audit does not inspect the theorem type or infer that it proves an external empirical claim. `provedClaim@value.true` is always rejected for external claim nodes.
