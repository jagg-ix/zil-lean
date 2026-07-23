# ZIL native authorization decision v1

## Request

```lean
structure Request where
  object : Term
  relation : Name
  subject : Term
  attrs : Array Attribute
```

The request must be ground. Its relation-engine form is:

```text
object -- relation --> subject
```

matching source syntax:

```text
object#relation@subject
```

## Evaluation

Given one valid `Zil.Program`:

1. lower tuples and declarations to base facts;
2. include source rules and userset traversal rules;
3. compute checked stratified closure;
4. compare the request with facts using semantic equality.

## Sources

```text
direct   request is present in base facts
derived  request is absent from base facts and present in closure
none     request is absent from closure
```

## Report

```text
ZIL-AUTHORIZATION\t1
decision\t<allow|deny>
source\t<direct|derived|none>
object\t<object>
relation\t<canonical relation>
subject\t<subject>
base-facts\t<count>
closed-facts\t<count>
deriving-rules\t<comma-separated rule names>
```

`deriving-rules` contains rules whose conclusion relation matches a derived request. It does not assert that each listed rule participated in the specific derivation.

## Exit status

```text
0 allow
1 deny or checked evaluation error
2 invalid CLI form
```

## Attribute policy

Semantic equality includes attributes. An attribute-free CLI request does not match an attributed relation. API callers may construct attributed requests explicitly.
