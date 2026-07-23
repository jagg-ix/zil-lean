# Stratified negation

The native source language supports absence checks with `NOT` in rule and query
bodies.

```zc
RULE activeViewer:
IF ?doc#viewer@?user AND NOT ?user#suspended@status:true
THEN ?doc#active_viewer@?user.

QUERY activeViewers:
FIND ?user WHERE doc:readme#viewer@?user AND NOT ?user#suspended@status:true.
```

`NOT atom` succeeds for one positive binding when no matching fact exists.

## Core representation

Rules and queries keep positive and negative premises separately:

```lean
structure Rule where
  premises : Array RelExpr
  negativePremises : Array RelExpr
  conclusion : RelExpr

structure Query where
  premises : Array RelExpr
  negativePremises : Array RelExpr
```

Canonical rule codecs emit negative rows as:

```text
negative<TAB>rel<TAB>...
```

Older encoded rules without negative rows remain valid positive Horn rules.

## Safety

Every variable used by a negative premise or a rule head must already be bound by
a positive premise.

```zc
RULE unsafe:
IF ?doc#viewer@?user AND NOT ?other#suspended@status:true
THEN ?doc#active_viewer@?user.
```

The parser rejects this rule because `?other` has no positive binding.

Queries apply the same condition. Every `FIND` variable must also be positively
bound.

## Dependency graph

For each rule with head relation `h`:

- a positive body relation `p` adds `p → h` with weight 0;
- a negative body relation `n` adds `n → h` with weight 1.

A stratum assignment must satisfy:

```text
level(h) ≥ level(p)
level(h) ≥ level(n) + 1
```

`Zil.Engine.stratify` computes these levels. An additional relaxation after the
relation count detects a strict dependency cycle.

```zc
RULE deriveA:
IF ?x#link@?y AND NOT ?x#b@?y
THEN ?x#a@?y.

RULE deriveB:
IF ?x#link@?y AND NOT ?x#a@?y
THEN ?x#b@?y.
```

This program is rejected because `a` and `b` depend negatively on each other.

## Evaluation

`Zil.Engine.closureChecked` evaluates strata from lowest to highest.

Within one stratum:

1. positive rule applications grow until a fixpoint or the configured fuel bound;
2. negative lookups use the completed facts available when the stratum began;
3. derived facts become available to higher strata.

This keeps absence checks stable while positive recursion remains available
inside each stratum.

The compatibility function `Zil.Engine.closure` returns the original supplied
facts when a hand-built rule set is unsafe or non-stratifiable. Parser-produced
programs are checked before execution, and callers that require diagnostics
should use `closureChecked`.

## Typed profiles

Typed rule validation checks positive premises, negative premises, rule safety,
and the conclusion against the active relation signatures.

## Validation

```bash
lake build
lake exe zilLeanTests
lake exe zil -- compile model.zc -
```
