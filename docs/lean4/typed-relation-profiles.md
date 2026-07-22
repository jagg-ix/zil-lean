# Typed relation profiles

Lean-native ZIL rules can now be checked against versioned relation signatures.
This prevents a relation from being accepted solely because its three tokens parse.

## Research profile

The initial `Zil.Profile.research` profile declares signatures such as:

```text
formalizes    : Declaration -> Claim
requires      : Declaration -> Requirement
requiresClaim : Claim -> Requirement
supportedBy   : Declaration -> EvidenceSource
supportedBy   : Claim -> EvidenceSource
```

Profiles remain outside the proof kernel's mathematical vocabulary. They validate
knowledge-model structure; they do not prove the represented scientific claim.

## Typed rule syntax

```lean
zil_typed_rule typedSchwarzschildRequirement using Zil.Profile.research where
  variables
    declaration : declaration
    claim : claim
    requirement : requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

#guard typedSchwarzschildRequirement.valid
```

The generated declaration has type `Zil.TypedRule`. It contains:

- the selected profile and profile version;
- variable-to-kind declarations;
- the canonical `Zil.Rule` produced by native syntax.

## Category errors

This rule parses but fails profile validation:

```lean
zil_typed_rule invalidFormalizesRequirement using Zil.Profile.research where
  variables
    declaration : declaration
    requirement : requirement
  premises
    declaration ⟶[formalizes] requirement
  conclusion
    declaration ⟶[formalizes] requirement

#guard !invalidFormalizesRequirement.valid
```

`formalizes` requires a `Claim` object, not a `Requirement`.

## Ground-node inference

Ground nodes use stable namespace prefixes:

```text
lean.*        -> Declaration
claim.*       -> Claim
requirement.* -> Requirement
paper.*       -> EvidenceSource
source.*      -> EvidenceSource
concept.*     -> Concept
file.*        -> File
theorem.*     -> Theorem
```

Unknown prefixes fail typed validation rather than being guessed.

## Compatibility

Existing `zil_rule` declarations remain available as untyped graph rules. This PR
adds an opt-in typed layer and does not reinterpret or silently reject legacy rules.

The Lean toolchain remains pinned to `leanprover/lean4:v4.31.0`.
