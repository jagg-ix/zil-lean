# ZIL first-order Horn resolution contract v0.1

Status: implemented, executable, and covered by the native Lean test suite.

This document is the reusable contract for the `Zil.Horn` layer. Update it when
the accepted syntax, search order, result shape, or proof boundary changes.

## Purpose and scope

`Zil.Horn` lets ZIL Lean load and execute the pure definite-Horn programs in
HORC while preserving the existing Datalog implementation. The layers serve
different operational needs:

| Layer | Terms | Evaluation | Termination model |
|---|---|---|---|
| `Zil.Datalog` | finite Datalog values | bottom-up fixed point | finite-domain workloads |
| `Zil.Horn` | nested first-order constructor terms | top-down SLD search | explicit clause-application bound |

The Horn layer models lists, trees, Peano arithmetic, automata, Turing-machine
configurations, abstract interpreters, and encoded Horn syntax without forcing
those structures into ground Datalog values.

## Module surface

Import the complete API with:

```lean
import Zil.Horn
```

The implementation is split by responsibility:

| Module | Contract |
|---|---|
| `Zil.Horn.Basic` | `Term`, `Atom`, `Clause`, ordered `Program`, and substitutions |
| `Zil.Horn.Unify` | substitution, occurs check, term/atom unification, projection, rendering |
| `Zil.Horn.Resolution` | bounded SLD search, traces, solutions, cutoff state, semantics |
| `Zil.Horn.Certificate` | independent proof-tree replay and soundness theorems |
| `Zil.Horn.Completeness` | declarative/certificate equivalence and replay completeness |
| `Zil.Horn.Parser` | parser for the HORC `.hn` surface language |
| `Zil.Horn.Tactic.Solve` | `horn_solve` and certified `horn_certify` tactics |
| `Zil.CLI.HornMain` | `zilHorc` file/query command |

`Zil.lean` publicly imports `Zil.Horn`, so downstream users may also use the
Horn API through `import Zil`.

## Data model

A term is either a named variable or a constructor application:

```lean
inductive Term where
  | variable (name : String)
  | app (symbol : String) (arguments : List Term)
```

A constant is an application with no arguments. An atom keeps its predicate
symbol separate from its term arguments. A clause has one head and zero or more
body atoms; an empty body is a fact. A program is an ordered list of clauses.
Successful solutions also contain a `Derivation` proof forest. Each tree node
records an original source clause, its instance substitution, and one child for
each body atom.

Clause order is part of the operational contract. Reordering a program may
change answer order or whether a depth-first branch reaches an answer within a
given bound.

## Accepted HORC syntax

The parser accepts the pure Prolog subset used by the HORC `.hn` files:

```text
program ::= clause+
clause  ::= atom "."
          | atom ":-" atom ("," atom)* "."
query   ::= atom ("," atom)* "."?
atom    ::= identifier
          | identifier "(" (term ("," term)*)? ")"
term    ::= variable
          | identifier
          | identifier "(" (term ("," term)*)? ")"
```

Identifiers contain letters, digits, or `_`. Names beginning with an uppercase
letter or `_` are variables. Each bare `_` occurrence is fresh. Other names are
predicate or constructor symbols. `%` starts a line comment.

The parser does not accept quoted atoms, infix operators, bracket-list sugar,
strings, floats, disjunction, negation, cut, extra-logical predicates, or Prolog
built-ins. These are rejected rather than assigned an approximate meaning.

## Unification contract

`unifyTerm` and `unifyAtom` implement symmetric first-order unification.

- Existing bindings are applied before each comparison.
- Constructor names and arities must match.
- Variable bindings undergo an occurs check.
- A failed symbol, arity, or occurs check returns `none`.
- Successful solver-created substitutions are acyclic and can be normalized.

`Term.substitute` is partial at the Lean implementation level because arbitrary
callers can construct cyclic substitution lists. Substitutions produced through
the unifier satisfy the acyclicity invariant enforced by `bind`.

## SLD-resolution contract

`solveDepth program goals limit` performs SLD resolution as follows:

1. Select the leftmost goal.
2. Visit source clauses in program order.
3. Standardize each candidate clause apart.
4. Unify the selected goal with the renamed clause head.
5. On success, prepend the clause body to the remaining goals.
6. Explore that branch depth-first, then backtrack to later clauses.

The depth is the number of clause applications. Resolving a fact consumes one
unit. An empty goal list succeeds without consuming another unit.

The returned `SearchResult` contains:

- every solution reached within the bound;
- bindings projected to variables in the original query;
- the successful branch's `ResolutionStep` trace;
- a declarative proof-tree certificate for each query goal;
- `cutoff = true` when at least one nonempty branch reached the bound.

Therefore an empty result with `cutoff = false` is finite failure for the
explored search tree, while an empty result with `cutoff = true` means only “no
answer within this bound.” Duplicate logical answers are retained when they
arise from distinct derivations.

`firstSolutionUpTo` performs finite iterative deepening from depth zero through
the caller-supplied maximum. No API claims termination for an arbitrary Horn
program.

## Meta-interpretation

Terms, atoms, clauses, and programs are ordinary Lean data. A Horn program may
therefore encode Horn syntax and relations over that syntax. The original
HORC `horn.hn` self-model parses and runs unchanged through `zilHorc`.

This is object-language reflection: the interpreted program reasons about an
encoding of Horn forms. It does not mutate Lean's environment or bypass Lean's
kernel.

## Proof and certificate boundary

The current layer provides two deliberately distinct propositions:

- `Entails program atom` is an inductive, declarative reading of definite-clause
  consequence and is intended for semantic proofs.
- `HasSolution program goals limit` states that bounded executable search found
  a solution.
- `HasCertifiedSolution program goals limit` states that bounded search found a
  solution whose proof forest passed independent replay.

For a closed, reducible `HasSolution` goal, `horn_solve` unfolds the proposition
and uses Lean's native decision procedure. Lean checks the resulting proof, so
the bounded result is not an unchecked assertion.

For semantic consumers, `solveCertifiedDepth` filters answers through
`checkDerivation`. The checker uses only the program, instantiated query, and
proof tree. It does not trust the SLD trace, the unifier result, or resolver
control flow. Its soundness chain is machine-checked:

```text
certificateValid = true
  -> ValidDerivations
  -> Entails for every instantiated query atom
```

The principal declarations are `checkDerivation_sound`,
`ValidDerivation.sound`, `Solution.certificateValid_entails`, and the generic
`solveCertifiedDepth_entails` theorem. `horn_certify` proves closed
`HasCertifiedSolution` goals by computation. The CLI exposes only certified
answers and aborts if certification would remove a raw solver answer.

The proof-tree system is also complete for finite declarative proofs:

```text
Entails program goal
  <-> exists derivation, ValidDerivation program goal derivation
  <-> exists derivation and fuel,
       checkDerivation fuel program goal derivation = true
```

`Entails.hasDerivation` constructs the certificate existentially.
`ValidDerivation.check_complete` proves that sufficient replay fuel exists,
and `entails_iff_exists_checkedDerivation` combines completeness with the
soundness direction. Replay acceptance is monotone in its fuel bound.

Version 0.1 now claims soundness for answers returned by
`solveCertifiedDepth` and completeness of the independently checked proof-tree
calculus. It does **not** yet claim:

- that the lower-level, unfiltered `solveDepth` API is itself proof-producing;
- automatic SLD-search completeness from `Entails` without a supplied
  certificate;
- termination of arbitrary Horn programs;
- that an operational `ResolutionStep` trace is a proof object (the separate
  `Derivation` tree is the checked certificate).

The remaining automatic-search theorem requires a formal lifting lemma for the
occurs-check unifier: any declarative clause instance must be represented by
the computed most-general unifier after standardization apart. That result and
any stronger termination theorem must be added explicitly and regression-tested.
The executable limit and cutoff bit remain part of the public contract.

## CLI contract

```text
zilHorc <program.hn> <query> [depth]
```

The default depth is 32. The command independently validates each proof tree,
prints each projected substitution with `[certified]` and its derivation depth,
then reports either a cutoff warning or that no branch was cut off.

Exit statuses are:

| Status | Meaning |
|---:|---|
| 0 | at least one solution was found |
| 1 | no solution was found, or parsing/runtime failed |
| 2 | command usage was invalid |

Because finite failure and errors currently share status 1, automation should
inspect standard output/error when it must distinguish them.

## Compatibility baseline

The following HORC models are the v0.1 compatibility fixtures:

| Model | Capability exercised | Example query |
|---|---|---|
| `src/horn/list.hn` | constructors and recursive lists | `member(X, cons(nil,1))` |
| `src/horn/map.hn` | backtracking and multiple bindings | `maps_to(cons(cons(nil,a,0),b,1), K, V)` |
| `src/horn/tm.hn` | Peano-like recursive terms | `natural(successor_natural(zero_natural))` |
| `src/horn/horn.hn` | encoded Horn syntax/meta-model | `variable(form_variable(empty_word))` |

The native Lean tests also cover occurs-check rejection, recursive success,
multiple answers, depth cutoff, iterative deepening, parsing, and `horn_solve`.

## Change checklist

When extending this contract:

1. Preserve old Datalog behavior and imports.
2. Specify any new syntax before accepting it in the parser.
3. State whether a feature is logical, operational, or extra-logical.
4. Add closed native tests for successful and failing cases.
5. Run `lake build` and `lake exe zilLeanTests`.
6. Re-run all four HORC compatibility queries above.
7. Update the proof-boundary section when a theorem is added or weakened.
