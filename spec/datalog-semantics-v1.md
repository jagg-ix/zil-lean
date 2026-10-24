# Semantics, checked evaluation and certificates for the Lean-embedded Datalog (v1)

Status: implemented in `Zil/Datalog/LeastModel.lean`, `Checked.lean` and `Certify.lean`; guards in `Zil/Test/DatalogChecked.lean` and
`Zil/Test/DatalogCertify.lean`. The design follows Tantow, Gerlach, Mennicke and Krötzsch, "Verifying Datalog Reasoning with Lean"
(ITP 2025, LIPIcs article 36, DOI 10.4230/LIPIcs.ITP.2025.36).

This page covers `Zil.Datalog.Program` (atoms with an object, a relation, a subject and attributes; rules with positive and negative
literals). The native engine (`Zil.Engine`, `bin/zil`) works on a different representation; `derivation-provenance-v1.md` describes its
traces, and the zil-lib repository checks them with `zilLib certify`.

## Definitions

* A **model** of a program is a set of atoms that contains the program's facts and is closed under its rules: every atom that a rule
  derives from the set, reading the rule's negative literals against the same set, is in the set (`IsModel`).
* A fact has a **derivation** when it is a fact of the program, or a rule derives it from atoms that have derivations (`Derives`; with the
  negative literals read against an explicit reference set, `DerivesUnder`).
* For a program **without negation**, the semantics is the **least model**: the atoms that belong to every model. It is also the set of
  atoms with a derivation.
* For a program **with negation**, a set `S` is a **stable model** when it is a model and every atom of `S` has a derivation in which the
  negative literals are read against `S` (`IsStableModel`). A stratified program has exactly one stable model (`stable_unique`, below).
* The relations are **stratified** when they can be numbered so that no positive literal of a rule is above its head and every negative
  literal is strictly below it (`Program.StrataValid`). `Program.strataValid` checks that the numbering the evaluator computes
  (`Program.stratumOf`) has this property; the theorem holds for whatever numbering passes, so nothing is assumed about how it is computed.

## Theorems (`Zil.Datalog.LeastModel`)

| Theorem | Statement |
|---|---|
| `derives_mem_model` | for a program without negation, every atom with a derivation belongs to every model (paper, Lemma 2) |
| `leastModel_of_sound_model` | a model that consists of atoms with derivations is inside every model and is exactly the set of atoms with a derivation (paper, Lemma 1 and the equivalence of the two semantics) |
| `isStableModel_iff` | `S` is stable exactly when `S` is a model and `a ∈ S ↔ DerivesUnder program S a` |
| `isStableModel_iff_sound` | for a program without negation, stable and least model coincide |
| `stable_unique` (`Zil.Datalog.Stratified`) | if the strata respect the rules, two stable models contain the same atoms |

## Matching is what it says (`Zil.Datalog.Matching`)

`unify` and `instantiate` decide what a rule means in the evaluator. The paper (section 3.1) reads a rule without a procedure: take every
**grounding**, a total assignment of values to variables; the rule fires under it when each positive literal, with the grounding applied,
is satisfied by a fact (same relation, object and subject, and every attribute of the pattern on the fact with the grounded value) and no
negative literal is satisfied by an atom of the reference set. `Matches g p a` is that satisfaction.

| Theorem | Statement |
|---|---|
| `unify_sound` | if `unify p a σ` succeeds with `σ'`, then `σ'` keeps every binding of `σ`, and every grounding that agrees with `σ'` matches |
| `unify_complete` | if a grounding that agrees with `σ` matches, `unify` succeeds, and its result keeps `σ` and agrees with the grounding |
| `unify_binds` | a successful `unify` binds every variable of the pattern |
| `bodyMatches_sound`, `bodyMatches_complete` | the same for a body, one literal after the other |
| `mem_applyRuleUnder_iff_ground` | for a safe rule, the atoms `applyRuleUnder` produces are exactly the heads of the groundings under which the rule fires |
| `isModel_iff_ground`, `derivesUnder_iff_ground`, `isStableModel_iff_ground` | for a safe program, models, derivations and stable models are the same as when read with groundings |

A rule is safe when its head and its negative literals use only variables that a positive literal has (`Rule.isSafe`; the parser and the
`zil_rule` command require it). So nothing in the definitions above depends on how `unify` is written.

## The evaluator's result is the stable model (`Zil.Datalog.Perfect`)

`deriveProgramChecked` saturates the strata in order, reading the negative literals of a rule in stratum `k` against what the strata
below `k` produced. It also checks that the numbering of the strata respects the rules (`Program.strataValid`), and returns an error if it
does not. The result is the stable model:

| Theorem | Statement |
|---|---|
| `deriveProgramChecked_isStableModel` | if `deriveProgramChecked` returns a set, it is a stable model: every fact has a derivation whose negative literals are read against the whole result |
| `deriveProgramChecked_unique` | every stable model of the program has the same atoms |
| `evaluator_eq_certificate` | the evaluator's set and the atoms of any certificate the checker accepts are the same set |

The argument: a stratum adds only facts of its own relations (`saturateStrata_adds`), and a negative literal of a rule in stratum `k` is over
a relation of a stratum below `k`, so every fact of the final result that the literal could match was already there when the rule fired
(`saturateStrata_derivesUnder`).

## Evaluation that says when it is incomplete (`Zil.Datalog.Checked`)

`derive`, `deriveStratified`, `query` and `holds` apply the rules a fixed number of times (32 by default) and return what they have.
A rule that extends a path by one step per round needs as many rounds as the path has steps, so a longer path lost its end and `holds`
answered `false` for a fact that follows. These functions stay as they were, for proofs and tools that fix the bound.

`deriveProgramChecked`, `queryChecked` and `holdsChecked` stop when a round adds nothing and fail when the bound (`defaultFuel`,
one million rounds; the round that finds nothing counts) is reached first, or when the program is not stratified. `#zil_query` uses them.

| Theorem | Statement |
|---|---|
| `deriveProgramChecked_ok` | a result is a stratified model of the program and every atom in it has a derivation |
| `deriveProgramChecked_leastModel` | for a program without negation the result is the least model |
| `holdsChecked_iff` | for a program without negation, `holdsChecked` answers `true` exactly when the atom has a derivation |
| `holds_of_checked` | for any stratified program, a `true` answer means the atom has a derivation |
| `not_holds_of_checked` | for a program without negation, a `false` answer means the atom has no derivation: a negative answer is proved too |

The tactic `zil_solve` closes a goal `Holds program atom` by `holds_of_checked` (it used the 32-round evaluator, so it failed for a derivation
of more than 32 rounds), and `zil_refute` closes `¬ Holds program atom` for a program without negation by `not_holds_of_checked`. Both
run the evaluation with `native_decide`.

## Certificates (`Zil.Datalog.Certify`)

A certificate is a list of nodes: an atom, and either nothing (a fact of the program) or the name of a rule and the numbers of the
earlier nodes that its positive literals matched, in order. `checkCertificate program certificate` checks that

1. every node is justified by nodes before it (the paper's ordered proof graph, which makes a circular argument impossible), the
   negative literals of the rule being absent from the set of all nodes;
2. the facts of the program are among the nodes;
3. no rule derives an atom outside the nodes (the paper's model check);
4. the strata of the program respect its rules (`Program.strataValid`).

| Theorem | Statement |
|---|---|
| `checkCertificate_sound` | if the check says yes, the atoms of the certificate are a stable model of the program |
| `checkCertificate_unique` | every stable model of the program has the same atoms: the answer is the only one |
| `checkCertificate_leastModel` | for a program without negation they are the least model, and an atom is among them exactly when it has a derivation |

`certifyProgram` makes a certificate by running the checked evaluation and adding the facts round by round. It is not trusted: the
checker accepts or refuses whatever it is given. The guards cover a chain, a program with negation, and nine ways to change a
certificate (an atom, a rule name, a premise out of range, a premise that comes later, a wrong number of premises, a database fact that
is not one, a missing fact, a missing rule consequence, an extra node), each of which the checker refuses.

## What is trusted

* nothing about matching beyond `Matches`, the grounding reading above: `unify` and `instantiate` are proved to compute it for safe rules;
* Lean's kernel, and the three axioms of classical logic (`propext`, `Classical.choice`, `Quot.sound`); a guard checks that no theorem of
  these files uses another axiom or `sorry`.

Not proved: that the native engine (`Zil.Engine`, a different and indexed implementation) computes the same set as `deriveProgramChecked`
(they are compared on random programs in the zil-lib repository, and a certificate checked with `zilLib certify --verified` settles it
for one program); that the engine's native checker, `zilLib certify`, is correct (it is tested, not proved); the existence of a
certificate for every entailed atom (`certifyProgram` is tested); that a rule that is not safe means anything (the theorems about
matching are for safe rules, and unsafe rules are refused where programs are read).

## Differences from the paper

The paper proves the model check complete and the proof graph acyclic with a depth-first search over a graph model, for programs without
negation, and measures an implementation that uses hash maps. Here the order of the nodes gives acyclicity directly (the paper's section
4.4), negation is handled by reading negative literals against the certified set (a stable-model argument), the checker is a plain list
implementation written for proof rather than speed, and performance is not a goal of this module.
