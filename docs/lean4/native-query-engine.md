# Native query and Horn closure engine

The Lean runtime can now evaluate the canonical relational IR directly.

## Scope

`Zil.Engine.Query` provides:

- variable bindings;
- relation unification;
- conjunctive premise matching;
- single-head Horn-rule application;
- semantic fact deduplication;
- bounded least-fixpoint closure;
- conjunctive query solving;
- environment-backed query execution.

The engine operates on `Zil.RelExpr`, `Zil.Rule`, and `Zil.Query`. It does not introduce a second relation representation.

## Closure

```lean
let closed := Zil.Engine.closure facts rules 64
```

The optional fuel is a defensive bound. Evaluation stops earlier when a step adds no new semantic fact.

Facts are deduplicated using `RelExpr.semanticallyEqual`, so source metadata does not create duplicate logical facts.

## Environment execution

```lean
run_cmd do
  let env ← getEnv
  let facts := Zil.Engine.closureOfEnvironment env
  -- inspect or validate facts
```

Imported facts and rules are read from the persistent environment extension introduced in PR #5.

## Queries

```lean
let query : Zil.Query :=
  { name := `requirements
    variables := #[`claim, `requirement]
    select := #[`requirement]
    premises := #[
      Zil.RelExpr.mk'
        (.variable `claim)
        `zil.requiresClaim
        (.variable `requirement)
    ] }

let answers := Zil.Engine.solve closed query
```

Each result is a binding array from variable names to canonical terms.

## Trust boundary

Derived facts are graph consequences. They are not Lean theorems and do not claim kernel certification. The engine preserves the existing `.graphDerived` distinction.

## Validation

```bash
lake build
lake exe zilLeanTests
```

The fixtures cover multi-premise inference, closure termination, semantic deduplication, and conjunctive query answers.
