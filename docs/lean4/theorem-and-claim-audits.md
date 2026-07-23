# Native theorem-contract and claim audits

The native theorem audit separates three distinct questions:

1. Is a theorem contract structurally non-vacuous?
2. Does a high-criticality theorem carry explicit proof evidence?
3. Is an external claim supported without being falsely promoted to proved?

## Command

```bash
bin/zil theorem-audit examples/theorem-audit/contracts.zc
```

Write a report with:

```bash
bin/zil theorem-audit \
  examples/theorem-audit/contracts.zc \
  /tmp/theorem-audit.txt
```

## Theorem contract discovery

A theorem is a node with:

```zc
theorem:x#kind@entity:theorem.
```

The audit reads:

```text
requires_assumption
requires_lemma
ensures
criticality
unconditional
proof_token
validated_by
proves
```

## Non-vacuity

A theorem contract is non-vacuous when at least one of these is true:

- it requires an assumption;
- it requires a lemma;
- it explicitly declares `unconditional@value:true`.

A theorem with no assumptions or lemmas is therefore not silently converted into a `true` precondition. It must explicitly state that it is unconditional.

Every theorem also needs at least one `ensures` guarantee.

Referenced assumptions and lemmas must be declared with:

```text
kind -> entity.assumption
kind -> entity.lemma
```

## Critical proof evidence

The default criticality is `low`.

High and critical theorem contracts require at least one relation under:

```text
proof_token
validated_by
proves
```

This requirement establishes an explicit evidence link. The linked producer remains responsible for checking the proof artifact or Lean declaration.

## External claims

A claim is a node with:

```zc
claim:x#kind@entity:claim.
```

Every claim needs at least one `supported_by` relation. Support targets are classified by their declared kind:

```text
kernel       theorem or proof
empirical    experiment, dataset, or measurement
documentary  document, paper, source, or evidence
graph        another declared project node
unknown      no declared kind
```

Unknown support kinds fail the audit because their evidentiary role is not stated.

## Hard trust boundary

An external claim may be supported, validated, corroborated, or connected to a theorem. It may not assert:

```zc
claim:x#proved_claim@value:true.
```

That relation fails with:

```text
external-claim-proof-boundary
```

A supporting kernel theorem proves its Lean statement. It does not automatically prove that an empirical interpretation, measurement claim, or scientific narrative is true.

## Report

`ZIL-THEOREM-AUDIT/1` includes:

- theorem and claim counts;
- theorem criticality and non-vacuity status;
- assumptions, lemmas, guarantees, and proof evidence;
- external claim support classes;
- exact issue codes;
- aggregate pass/fail.

## Common failures

```text
vacuous-contract
guarantee-missing
missing-assumption:<node>
missing-lemma:<node>
proof-evidence-missing
support-missing
support-kind-missing:<node>
external-claim-proof-boundary
```

## Exit status

```text
0 every theorem contract and external claim passes
1 audit failure or evaluation error
2 invalid command shape
```

An empty theorem/claim set passes. A higher-level release policy may require a minimum count.

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil theorem-audit examples/theorem-audit/contracts.zc
```
