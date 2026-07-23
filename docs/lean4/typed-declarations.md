# Typed declarations

The native frontend accepts the higher-level declaration forms already used by
the original ZIL runtime:

```text
SERVICE HOST DATASOURCE METRIC POLICY EVENT PROVIDER
TM_ATOM LTS_ATOM REFINES CORRESPONDS PROOF_OBLIGATION
FORMALIZATION_TARGET LANGUAGE_PROFILE GRAMMAR_PROFILE
PARSER_ADAPTER DSL_PROFILE QUERY_PACK
```

Each declaration is parsed into a typed `Zil.Declaration`, validated, and then
lowered deterministically into the same `RelExpr` facts used by tuples, rules,
and queries.

## Example

```zc
SERVICE db [env=prod].
SERVICE api [env=prod, uses=service:db].
DATASOURCE app_metrics [type=rest, format=json].
METRIC latency [source=datasource:app_metrics, unit=ms].
```

The API service produces, among other facts:

```text
service.api -- uses --> service.db
service.db -- usedBy --> service.api
service.api -- dependsOn --> service.db
```

## Typed values

Declaration attributes support:

- scalar strings, integers, decimals, booleans, and named terms;
- lists such as `["ops", "deploy"]`;
- sets such as `#{q0 qa qr}`;
- maps such as TM and LTS transition maps.

These rich values are kept separate from ordinary tuple attributes so existing
relation codecs remain stable.

## Validation

Local validation checks:

- required fields for each declaration kind;
- enum domains matching the existing Clojure runtime;
- duplicate keys;
- ground values;
- TM state/alphabet/halting-state consistency;
- LTS state and initial-state consistency.

Program-level validation checks:

- duplicate declaration identities;
- service dependency references;
- service dependency cycles;
- metric datasource references;
- provider references;
- language, grammar, parser, query-pack, and refinement references.

## Lowering

Every declaration emits a `kind` relation. Scalar attributes become relations
from the declaration entity to a stable value node. Special fields have richer
lowering:

- `uses` and `used_by` emit inverse dependency facts;
- service `uses` also emits `dependsOn`;
- provider bindings emit `providesFor` inverses;
- TM transitions emit indexed `transition` facts with transition attributes;
- LTS transitions emit indexed `edge` facts.

## Macros

Macros expand before declaration parsing, so reusable declaration templates work
with the same validation and lowering:

```zc
MACRO service(name):
EMIT SERVICE {{name}} [env=prod].
ENDMACRO.

USE service(api).
```

## Lean integration

Generated modules retain declaration values and register their lowered facts:

```lean
private def sourceDeclaration0 : Zil.Declaration := ...

def sourceDeclarations : Array Zil.Declaration := #[sourceDeclaration0]

#zil_check_declarations sourceDeclarations
zil_register_declaration sourceDeclaration0
```

The generated `completeSourceProgram` extends the tuple/rule/query program with
its typed declarations.

## Native APIs

```lean
Zil.Declaration.issues
Zil.Declaration.lower
Zil.DeclarationSet.issues
Zil.DeclarationSet.lower
Zil.Parser.Declaration.parseLine
Zil.Parser.DeclarationProgram.parseText
```

## Validation commands

```bash
lake build
lake exe zilLeanTests
lake exe zil -- compile examples/declarations/native-stdlib.zc
```
