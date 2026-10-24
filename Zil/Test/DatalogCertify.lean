import Zil.Datalog.Certify
import Lean

/-!
# The certificate checker accepts what is right and refuses each way a certificate can be wrong

`checkCertificate_sound` proves that a certificate the checker accepts is a stable model of the program. These tests run the checker:
on certificates that `certifyProgram` makes (a chain, and a program with negation), and on the same certificates with one thing
changed, which the checker must refuse. The chain has 8 edges.
-/

open Zil.Datalog

private def steps : Nat := 8

private def node (i : Nat) : Value := .symbol s!"n{i}"
private def edge (i j : Nat) : Atom := { object := node i, relation := "edge", subject := node j }
private def reach (i j : Nat) : Atom := { object := node i, relation := "reach", subject := node j }
private def pattern (relation : String) (a b : String) : Pattern :=
  { object := .variable a, relation, subject := .variable b }

private def chain : Program where
  facts := (List.range steps).map fun i => edge i (i + 1)
  rules := [
    { name := "base", head := pattern "reach" "x" "y", literals := [.positive (pattern "edge" "x" "y")] },
    { name := "step", head := pattern "reach" "x" "z",
      literals := [.positive (pattern "reach" "x" "y"), .positive (pattern "edge" "y" "z")] }]

private def certificate (program : Program) : Certificate :=
  match certifyProgram program with | .ok cert => cert | .error _ => []

private def chainCert : Certificate := certificate chain

-- The program has 8 facts and the closure has 36 reach facts: 44 nodes.
#guard chainCert.length == 8 + (steps * (steps + 1)) / 2
#guard checkCertificate chain chainCert

-- One change, and the checker says no. Each case is a way a reasoner can be wrong.
private def replaceAt (cert : Certificate) (i : Nat) (f : CertNode → CertNode) : Certificate :=
  cert.mapIdx fun j n => if j == i then f n else n

private def derivedIndex : Nat := steps + 2 -- a node derived by rule `step`

-- a derived node with another atom than the rule gives
#guard !checkCertificate chain (replaceAt chainCert derivedIndex fun n => { n with atom := reach 3 1 })
-- a derived node that names a rule the program does not have
#guard !checkCertificate chain (replaceAt chainCert derivedIndex fun n =>
  { n with origin := n.origin.map fun (_, ids) => ("nonsense", ids) })
-- a derived node that names a premise number out of range
#guard !checkCertificate chain (replaceAt chainCert derivedIndex fun n =>
  { n with origin := n.origin.map fun (r, _) => (r, [1000, 1001]) })
-- a derived node whose premise comes later: a circular argument
#guard !checkCertificate chain (replaceAt chainCert derivedIndex fun n =>
  { n with origin := n.origin.map fun (r, _) => (r, [derivedIndex, 0]) })
-- a derived node with the wrong number of premises
#guard !checkCertificate chain (replaceAt chainCert derivedIndex fun n =>
  { n with origin := n.origin.map fun (r, ids) => (r, ids ++ [0]) })
-- a fact that is not in the program, given as if it were
#guard !checkCertificate chain (replaceAt chainCert 0 fun n => { n with atom := edge 7 0 })
-- a missing fact: the last node is dropped, so a rule still derives something outside the set
#guard !checkCertificate chain chainCert.dropLast
-- a missing fact of the program
#guard !checkCertificate chain (chainCert.drop 1)
-- an extra fact that nothing derives
#guard !checkCertificate chain (chainCert ++ [{ atom := reach 0 0, origin := some ("base", [0]) }])

/-- A program with a negative literal: the vertices that `n0` does not reach. -/
private def withNegation : Program where
  facts := chain.facts ++ (List.range (steps + 2)).map fun i => { object := node i, relation := "vertex", subject := .symbol "yes" }
  rules := chain.rules ++ [
    { name := "unreached", head := { object := .variable "x", relation := "unreached", subject := .value (.symbol "yes") },
      literals := [.positive { object := .variable "x", relation := "vertex", subject := .value (.symbol "yes") },
                   .negative { object := .value (node 0), relation := "reach", subject := .variable "x" }] }]

private def negationCert : Certificate := certificate withNegation

-- `n0` reaches n1 to n8; of the 10 vertices, `n0` and `n9` are not reached.
#guard (negationCert.filter (·.atom.relation == "unreached")).length == 2
#guard checkCertificate withNegation negationCert
-- Say that a reached vertex is unreached: its negative literal is false in the set.
#guard !checkCertificate withNegation
  (negationCert ++ [{ atom := { object := node 3, relation := "unreached", subject := .symbol "yes" },
                      origin := some ("unreached", [steps + 3 + 3]) }])
-- Leave out one unreached vertex: a rule still derives it.
#guard !checkCertificate withNegation
  (negationCert.filter fun n => n.atom != { object := node 9, relation := "unreached", subject := .symbol "yes" })

-- The strata of both programs respect their rules; a program that negates itself has none that do, and no certificate passes.
#guard chain.strataValid
#guard withNegation.strataValid
private def selfNegating : Program where
  facts := [edge 0 1]
  rules := [
    { name := "a", head := pattern "p" "x" "y", literals := [.positive (pattern "edge" "x" "y"), .negative (pattern "q" "x" "y")] },
    { name := "b", head := pattern "q" "x" "y", literals := [.positive (pattern "edge" "x" "y"), .negative (pattern "p" "x" "y")] }]
#guard !selfNegating.strataValid
#guard !checkCertificate selfNegating [{ atom := edge 0 1 }, { atom := reach 0 1, origin := some ("a", [0]) }]

-- The theorem, used: from the check to the semantics, for a concrete program. (`native_decide` runs the check.)
example : IsStableModel chain (chainCert.map (·.atom)) := checkCertificate_sound (by native_decide)

-- No other set of atoms is a stable model of the program with negation: the answer is unique.
example (other : Interpretation) (h : IsStableModel withNegation other) : ∀ a, a ∈ other ↔ a ∈ negationCert.map (·.atom) :=
  checkCertificate_unique (by native_decide) h

example : ∀ a, a ∈ chainCert.map (·.atom) ↔ Derives chain a := by
  have hpos : chain.IsPositive := by
    intro rule hrule
    simp only [chain, List.mem_cons, List.not_mem_nil, or_false] at hrule
    rcases hrule with rfl | rfl <;> rfl
  exact (checkCertificate_leastModel hpos (by native_decide)).2.2

-- The theorems use no axiom beyond the three of classical logic.
open Lean Elab Command in
run_cmd do
  for theoremName in [``checkCertificate_sound, ``checkCertificate_leastModel, ``checkCertificate_unique, ``stable_unique,
      ``derivesUnder_mem_of_agree, ``checkNodes_derives, ``nodeOk_derives, ``matchChain_bodyMatches] do
    let axioms ← liftCoreM <| collectAxioms theoremName
    for ax in axioms do
      unless ax == ``propext || ax == ``Classical.choice || ax == ``Quot.sound do
        throwError "{theoremName} depends on {ax}"
