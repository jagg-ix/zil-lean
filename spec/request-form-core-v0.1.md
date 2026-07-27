# Request Form Core v0.1 (Draft)

## 1. Goal

Define a formal request form where a requester asks for `<something>`, and
`<something>` can be:

1. data,
2. an action with side effects,
3. a compound/recursive structure combining simpler parts.

This profile is layered above ZIL core and lowers to canonical tuple facts.

## 2. Abstract Syntax

Let:

- `ReqId` be request identifiers,
- `NodeId` be request payload node identifiers,
- `CritId` be acceptance criterion identifiers,
- `EffId` be effect identifiers.

```
Request ::= <id: ReqId, requester: Actor, mode: Mode, root: NodeId, accepts: CritId*>
Mode    ::= dry_run | apply

Something ::=
    Data(NodeId, Schema)
  | Action(NodeId, Verb, Target, EffId*)
  | Compound(NodeId, Op, NodeId*)
  | Recursive(NodeId, Var, NodeId)

Op ::= seq | all | any | map | fold | custom

Effect ::= <id: EffId, kind: EffKind, target: Target>
EffKind ::= writes | emits | calls | external

Criterion ::= <id: CritId, expr: String>
```

## 3. Denotational View

### 3.1 Containment Closure

`contains` is the transitive closure over direct structural edges:

```
CONTAINS-BASE
parent contains child
---------------------
contains*(parent, child)

CONTAINS-STEP
contains*(x, y)   contains*(y, z)
-------------------------------
contains*(x, z)
```

### 3.2 Side-Effect Set

Direct effect set for an action node `a`:

```
DirectEffects(a) = { e | has_effect(a,e) }
```

Effect set for any node `n`:

```
Effects(n) = DirectEffects(n) U ⋃ { Effects(c) | contains*(n,c) }
```

Request-level side effects:

```
ReqEffects(r) = Effects(root(r))
```

### 3.3 Recursive Form

Recursive payloads use least-fixpoint interpretation:

```
Recursive(n, X, body)  =>  Sem(n) = lfp F
where F(S) = Sem(body)[X := S]
```

This allows complex self-referential action plans to be represented without
forcing eager execution.

## 4. Operational Intent

Requests distinguish planning from application:

1. `mode=dry_run`:
   - MUST compute/describe candidate side effects,
   - MUST NOT apply effects.
2. `mode=apply`:
   - MAY execute effects, subject to acceptance criteria and policy checks.

Acceptance criteria are modeled as explicit criterion entities; evaluation can
be delegated to external engines and written back as facts/proofs.

## 5. ZIL Canonical Mapping

Canonical fact shapes:

- request:
  - `request:<id>#kind@entity:request.`
  - `request:<id>#requester@actor:<requester>.`
  - `request:<id>#mode@value:<mode>.`
  - `request:<id>#root@node:<root>.`
  - `request:<id>#accepts@criterion:<crit>.`
- nodes:
  - `node:<id>#kind@entity:data|action|compound|recursive.`
  - `node:<id>#contains@node:<child>.`
- effects:
  - `effect:<id>#kind@entity:effect.`
  - `effect:<id>#effect_kind@value:<kind>.`
  - `node:<action>#has_effect@effect:<id>.`
- criteria:
  - `criterion:<id>#kind@entity:criterion.`
  - `criterion:<id>#expr@value:"...".`

## 6. Derived Judgments (Typical)

```
REQ-SIDE-EFFECTFUL
r kind request    r contains* n    n has_effect e
-----------------------------------------------
r has_side_effect true

REQ-RECURSIVE
r kind request    r contains* n    n kind recursive
-----------------------------------------------
r is_recursive true

DRY-RUN-CONTRACT
r mode dry_run    r has_side_effect true
---------------------------------------
r execution_contract plan_only
```

## 7. Notes on Expressiveness

This profile intentionally separates:

1. structure (`something` graph),
2. intent (request mode + criteria),
3. effect semantics (effect entities),
4. execution/proof facts (optional external engines).

That separation keeps the form usable for simple requests and for complex,
recursive entities with side effects.
