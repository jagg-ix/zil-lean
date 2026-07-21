# ZIL Formal Core v0.1 (Normative Draft)

## 1. Status

This document is normative for the ZIL core language semantics in v0.1.

The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are to be
interpreted as described in RFC 2119.

This spec defines:

1. canonical syntax categories,
2. canonical core IR,
3. static well-formedness and safety,
4. stratified least-fixpoint execution semantics,
5. query semantics,
6. causal-time core constraints.

This spec does not define backend storage layout. Runtime mappings are defined in:

- `spec/runtime-datascript-profile-v0.1.md`

## 2. Scope and Layering

ZIL core is domain-agnostic. Domain declarations and domain profiles are layered
on top of core semantics and MUST lower to equivalent canonical facts.

References:

- `spec/zil-v0.1r1.md`
- `spec/time-core-v0.1.md`
- `docs/language-architecture.md`

## 3. Abstract Syntax

Let:

- `Name` be identifier tokens for module/rule/query/declaration names.
- `Rel` be relation identifiers.
- `Var` be variables, written as strings starting with `?` (for example `?x`).
- `Const` be non-variable terms.
- `Term ::= Var | Const`.

### 3.1 Core Terms

An atom is:

```
Atom ::= <object: Term, relation: Rel, subject: Term, attrs: AttrMap>
AttrMap ::= finite map Key -> Term
```

A literal is:

```
Literal ::= Pos(Atom) | Neg(Atom)
```

A rule is:

```
Rule ::= <name: Name, body: Literal*, head: Atom*>
```

A query is:

```
Query ::= <name: Name, find: Var+, where: Literal*>
```

A program is:

```
Program ::= <module: Name, facts: Atom*, rules: Rule*, queries: Query*, declarations: Decl*>
```

### 3.2 Surface Grammar (Core)

Concrete syntax accepted by the current parser includes:

```
MODULE <name>.

<object>#<relation>@<subject> [k1=v1, ...].

RULE <name>:
IF <lit1> AND ... AND <litN>
THEN <atom1> AND ... AND <atomM>.

QUERY <name>:
FIND ?x ?y ... WHERE <lit1> AND ... AND <litK>.
```

With:

- `NOT <atom>` for negative literals in bodies.
- optional `attrs` in atom form.
- `//` line comments stripped before parsing (outside string literals).

Normative parser references:

- `src/zil/core.clj` (`parse-atom`, `parse-rule-body`, `parse-find-line`, `parse-program`)

## 4. Canonical Core IR

A conforming implementation MUST compile to canonical IR equivalent to:

```
CompiledProgram ::= <module, facts, rules, queries, declarations, strata>
```

Where:

1. `facts` are canonical atoms.
2. rules are safety-checked and assigned a stratum index.
3. declarations are validated and lowered to canonical atoms before evaluation.

The lowering function is:

```
LowerDecls : Decl* -> Atom*
```

And extensional base facts are:

```
F0 = ParsedFacts U LowerDecls(Declarations)
```

## 5. Static Semantics

## 5.1 Rule Safety

Define:

- `vars(a)` = variables appearing in atom `a` (object, subject, attrs values).
- `vars_pos(body)` = union of vars of positive literals.
- `vars_neg(body)` = union of vars of negative literals.
- `vars_head(head)` = union of vars in head atoms.

A rule is safe iff:

1. `vars_neg(body) subseteq vars_pos(body)`,
2. `vars_head(head) subseteq vars_pos(body)`.

Inference form:

```
SAFE-RULE
vars_neg(B) subseteq vars_pos(B)    vars_head(H) subseteq vars_pos(B)
----------------------------------------------------------------------
                    safe(<name, B, H>)
```

Unsafe rules MUST be rejected at compile time.

## 5.2 Stratification

For each rule `r` with head relations `HeadRel(r)`, positive body relations
`PosRel(r)`, and negative body relations `NegRel(r)`, define weighted
dependencies:

1. for each `p in PosRel(r)`, `h in HeadRel(r)`: edge `(p -> h, 0)`,
2. for each `n in NegRel(r)`, `h in HeadRel(r)`: edge `(n -> h, 1)`.

A stratum assignment `str : Rel -> N` is valid iff:

1. `str(h) >= str(p)` for every `(p -> h, 0)`,
2. `str(h) >= str(n) + 1` for every `(n -> h, 1)`.

Inference form:

```
STRATIFIED
forall (p -> h,0) in E : str(h) >= str(p)
forall (n -> h,1) in E : str(h) >= str(n)+1
-------------------------------------------
               stratified(E, str)
```

If no valid `str` exists, the program MUST be rejected as non-stratifiable.

## 5.3 Declaration Validation (Core Boundary)

Declarations are outside core truth conditions, but if supported they MUST be:

1. validated by declaration-specific constraints,
2. lowered deterministically into canonical atoms.

Current declaration kinds and checks are defined in `src/zil/lower.clj`.

## 6. Dynamic Semantics

## 6.1 Substitutions and Matching

Let `sigma` be a finite map `Var -> Const`.

Judgment for term matching:

```
sigma |- t ~ v => sigma'
```

Rules:

```
MATCH-VAR-NEW
x notin dom(sigma)
------------------------------
sigma |- ?x ~ v => sigma[?x:=v]

MATCH-VAR-BOUND
sigma(?x) = v
---------------------
sigma |- ?x ~ v => sigma

MATCH-CONST
c = v
----------------
sigma |- c ~ v => sigma
```

If no rule applies, matching fails.

Attribute-map matching (`Apat` against `Afact`) succeeds iff all keys in `Apat`
exist in `Afact` and each value matches under substitution extension.

Atom matching judgment:

```
sigma |- AtomPat ~~ AtomFact => sigma'
```

Requires successful matching of object, subject, and attrs under same relation.

## 6.2 Literal Evaluation

Body evaluation uses two indexes:

- `I+` for positive lookup,
- `I-` for negative lookup.

Judgment:

```
I+, I- |- <B, E> => E'
```

Where `E` is a set of substitutions.

Rules:

```
BODY-EMPTY
-----------------------------
I+, I- |- <[], E> => E

BODY-POS
I+, I- |- <Rest, E1> => E2
E1 = { sigma' | sigma in E, f in I+[rel(a)], sigma |- a ~~ f => sigma' }
---------------------------------------------------------------------------
I+, I- |- <Pos(a)::Rest, E> => E2

BODY-NEG
I+, I- |- <Rest, E1> => E2
E1 = { sigma in E | not exists f in I-[rel(a)], sigma' . sigma |- a ~~ f => sigma' }
--------------------------------------------------------------------------------------
I+, I- |- <Neg(a)::Rest, E> => E2
```

Evaluation order is left-to-right over body literals.

## 6.3 Grounding

Grounding replaces head variables using a substitution.

Judgment:

```
sigma |- ground(a) => f
```

If any variable in head atom is unbound in `sigma`, grounding fails.

Safe rules (Section 5.1) guarantee this does not occur for accepted programs.

## 6.4 Rule Application

For a rule `r = <name, B, H>`:

```
derive(r, Icur, Ibase) =
  { f | sigma in EvalBody(Icur, Ibase, B), h in H, sigma |- ground(h) => f }
```

Where:

```
EvalBody(Icur, Ibase, B) = E
iff Icur, Ibase |- <B, {empty_subst}> => E
```

## 6.5 Per-Stratum Least Fixpoint

Given base fact set `B` and stratum rule set `Rs`:

```
I0 = B
Ik+1 = Ik U (Union over r in Rs of derive(r, Ik, B))
```

`lfp(B, Rs)` is the least `I` such that `I = Ik = Ik+1` for some `k`.

New facts from this stratum:

```
Delta(B, Rs) = lfp(B, Rs) \ B
```

## 6.6 Whole-Program Semantics

Let `S0 = F0` and strata in ascending order `s1 < s2 < ... < sn`.
Let `Rs` be rules with stratum `s`.

For `i = 1..n`:

```
Si = S(i-1) U Delta(S(i-1), Rsi)
```

Final model:

```
S* = Sn
```

Inference form:

```
EXEC
F0 from parsing/lowering   rules stratified into s1..sn
S0=F0   forall i: Si=Si-1 U Delta(Si-1,Rsi)
--------------------------------------------
            Program ==> S*
```

## 7. Query Semantics

For query `q = <name, find=[v1..vm], where=B>` over final facts `S*`:

```
E = EvalBody(S*, S*, B)
Rows = distinct([ sigma(v1), ..., sigma(vm) ] for sigma in E)
```

Result:

```
Answer(q,S*) = <vars=[v1..vm], rows=Rows>
```

## 8. Macro Expansion Semantics (Language-Level)

Macros are expanded before parsing/evaluation.

A macro definition binds:

```
name -> <params, emit_lines>
```

A use-site:

```
USE name(arg1,...,argN).
```

expands by positional substitution in each emit line:

```
{{param_i}} -> arg_i
```

Expansion is recursive and MUST terminate under an implementation-defined safety
limit (current implementation: 10000 expansion steps).

After expansion, resulting text MUST parse as standard program syntax.

## 9. Causal Time Core

Core causal relation:

```
before(e1,e2)
```

MUST satisfy:

1. irreflexive: not `before(e,e)`,
2. transitive: `before(a,b)` and `before(b,c)` implies `before(a,c)`,
3. acyclic.

Concurrency:

```
concurrent(e1,e2) <=> not before(e1,e2) and not before(e2,e1)
```

Clock schemes (vector, lamport, hybrid, relativistic profiles) are optional
representational overlays and MUST NOT contradict the causal core.

Reference:

- `spec/time-core-v0.1.md`

## 10. Conformance

An implementation conforms to ZIL Formal Core v0.1 iff it:

1. accepts canonical surface constructs in Section 3,
2. compiles to equivalent core IR (Section 4),
3. enforces safety and stratification checks (Section 5),
4. evaluates rules by stratified least-fixpoint semantics (Section 6),
5. answers queries per Section 7,
6. preserves causal-time axioms in Section 9.

Any extension layer (declarations, profiles, adapters) MUST preserve semantic
equivalence with core facts/rules/query behavior.
