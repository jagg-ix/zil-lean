# Canonical relational IR v0.1

## Status

Draft implementation contract for PR 2 of the Lean-native ZIL roadmap.

## Objective

All ZIL frontends must lower relations and Horn-style rules into one semantic representation before evaluation, query planning, linting, export, or Lean integration.

The following source forms must become equivalent:

```text
?declaration#formalizes@?claim
```

```lean
declaration ⟶[formalizes] claim
```

```clojure
{:subject "?declaration"
 :relation :formalizes
 :object "?claim"}
```

## Canonical relation expression

```clojure
{:ir/kind :relation
 :subject {:term/kind :var|:node ...}
 :relation :zil/formalizes
 :object {:term/kind :var|:node ...}}
```

Optional fields include:

- `:source` for provenance;
- `:attrs` for tuple attributes;
- `:neg?` for rule-body negation.

Provenance does not affect semantic equality.

## Direction convention

Canonical IR uses graph-oriented names:

```text
subject --relation--> object
```

The legacy tuple parser currently emits historical map keys named `:object` and `:subject`. The adapter `from-legacy-atom` is the only place where this naming mismatch should be interpreted.

## Relation names

Lean-facing camel case and legacy snake case normalize to the same qualified relation:

```text
requires_claim  -> :zil/requiresClaim
requiresClaim   -> :zil/requiresClaim
supported_by    -> :zil/supportedBy
supportedBy     -> :zil/supportedBy
```

Profile-qualified relations preserve their namespace.

## Canonical rule

```clojure
{:ir/kind :rule
 :rule/name "schwarzschildClaimRequirement"
 :rule/variables ["claim" "requirement" "declaration"]
 :rule/premises [...]
 :rule/conclusion ...
 :rule/trust :graph-derived}
```

Rule trust is explicit. A later PR will distinguish graph rules from Lean-kernel-certified rules.

## Acceptance criteria

1. Legacy and Lean-native forms compare equal after normalization.
2. Source metadata does not change semantic equality.
3. Missing relation fields fail with structured exceptions.
4. New consumers use canonical IR rather than introducing another tuple shape.
5. Existing execution behavior remains unchanged in this PR.
