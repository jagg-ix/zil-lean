# Native authorization decisions

The native frontend can answer exact Zanzibar-style authorization questions over ordinary ZIL tuples, usersets, and rules.

## Command

```bash
bin/zil authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

The command exits with:

```text
0  allow
1  deny or evaluation failure
2  invalid command shape
```

An optional final path writes the report to a file.

## Semantics

The request:

```text
object=doc:readme
relation=viewer
subject=user:11
```

is converted to the same native `RelExpr` used by the rule engine. Authorization then:

1. validates the parsed program and ground request;
2. computes checked stratified closure;
3. tests exact semantic relation equality;
4. classifies an allow as direct or derived.

A userset tuple such as:

```zc
doc:readme#viewer@group:eng#member.
```

combined with:

```zc
group:eng#member@user:11.
```

therefore authorizes `user:11` as a derived viewer.

## Decision source

```text
direct   the exact relation is a base fact
derived  the exact relation appears only after rule closure
none     the exact relation is absent from closure
```

For derived decisions, the report lists rules whose conclusion relation matches the requested relation. This is a candidate-rule inventory, not a full derivation proof. The current engine does not yet persist proof trees for individual closure facts.

## Attributes

The API supports request attributes. The CLI currently creates an attribute-free request, so an attributed grant is not treated as an exact match. This avoids silently ignoring policy conditions.

## Native API

```lean
Zil.Authorization.Request
Zil.Authorization.Decision
Zil.Authorization.decide
Zil.Authorization.render
```

## Validation

```bash
lake build
lake exe zilLeanTests
bin/zil authorize examples/authorization/access.zc doc:readme viewer user:11
bin/zil authorize examples/authorization/access.zc doc:readme viewer user:99
```
