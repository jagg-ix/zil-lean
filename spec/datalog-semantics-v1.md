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
  negative literals are read against `S` (`IsStableModel`). A stratified program has exactly one stable model, the one that evaluation
  stratum by stratum computes. That last statement is not proved here.

## Theorems (`Zil.Datalog.LeastModel`)

| Theorem | Statement |
|---|---|
| `derives_mem_model` | for a program without negation, every atom with a derivation belongs to every model (paper, Lemma 2) |
| `leastModel_of_sound_model` | a model that consists of atoms with derivations is inside every model and is exactly the set of atoms with a derivation (paper, Lemma 1 and the equivalence of the two semantics) |
| `isStableModel_iff` | `S` is stable exactly when `S` is a model and `a ∈ S ↔ DerivesUnder program S a` |
| `isStableModel_iff_sound` | for a program without negation, stable and least model coincide |

## Evaluation that says when it is incomplete (`Zil.Datalog.Checked`)

`derive`, `deriveStratified`, `query` and `holds` apply the rules a fixed number of times (32 by default) and return what they have.
A rule that extends a path by one step per round needs as many rounds as the path has steps, so a longer path lost its end and `holds`
answered `false` for a fact that follows. These functions stay as they were, for proofs that fix the bound (`zil_solve`).

`deriveProgramChecked`, `queryChecked` and `holdsChecked` stop when a round adds nothing and fail when the bound (`defaultFuel`,
one million rounds; the round that finds nothing counts) is reached first, or when the program is not stratified. `#zil_query` uses them.

| Theorem | Statement |
|---|---|
| `deriveProgramChecked_ok` | a result is a stratified model of the program and every atom in it has a derivation |
| `deriveProgramChecked_leastModel` | for a program without negation the result is the least model |
| `holdsChecked_iff` | for a program without negation, `holdsChecked` answers `true` exactly when the atom has a derivation |

## Certificates (`Zil.Datalog.Certify`)

A certificate is a list of nodes: an atom, and either nothing (a fact of the program) or the name of a rule and the numbers of the
earlier nodes that its positive literals matched, in order. `checkCertificate program certificate` checks that

1. every node is justified by nodes before it (the paper's ordered proof graph, which makes a circular argument impossible), the
   negative literals of the rule being absent from the set of all nodes;
2. the facts of the program are among the nodes;
3. no rule derives an atom outside the nodes (the paper's model check).

| Theorem | Statement |
|---|---|
| `checkCertificate_sound` | if the check says yes, the atoms of the certificate are a stable model of the program |
| `checkCertificate_leastModel` | for a program without negation they are the least model, and an atom is among them exactly when it has a derivation |

`certifyProgram` makes a certificate by running the checked evaluation and adding the facts round by round. It is not trusted: the
checker accepts or refuses whatever it is given. The guards cover a chain, a program with negation, and nine ways to change a
certificate (an atom, a rule name, a premise out of range, a premise that comes later, a wrong number of premises, a database fact that
is not one, a missing fact, a missing rule consequence, an extra node), each of which the checker refuses.

## What is trusted

* the matching functions `unify` and `instantiate`, which say what a rule means; the theorems are about rules as these functions read
  them, not about a separate account of matching;
* Lean's kernel, and the three axioms of classical logic (`propext`, `Classical.choice`, `Quot.sound`); a guard checks that no theorem of
  these files uses another axiom or `sorry`.

Not proved: that `unify` agrees with a declarative notion of matching (the paper's section 3.1); that the stable model of a stratified
program is unique and equals the stratum-by-stratum result; that the engine's native checker, `zilLib certify`, is correct (it is tested,
not proved); the existence of a certificate for every entailed atom (`certifyProgram` is tested).

## Differences from the paper

The paper proves the model check complete and the proof graph acyclic with a depth-first search over a graph model, for programs without
negation, and measures an implementation that uses hash maps. Here the order of the nodes gives acyclicity directly (the paper's section
4.4), negation is handled by reading negative literals against the certified set (a stable-model argument), the checker is a plain list
implementation written for proof rather than speed, and performance is not a goal of this module.
