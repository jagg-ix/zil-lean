import Zil.TheoremAudit
import Zil.Parser.DeclarationProgram

open Zil.TheoremAudit

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE theorem.audit.\n" ++
  "assumption:finite#kind@entity:assumption.\n" ++
  "lemma:closure#kind@entity:lemma.\n" ++
  "proof:valid#kind@entity:proof.\n" ++
  "document:paper#kind@entity:document.\n" ++
  "experiment:run#kind@entity:experiment.\n" ++
  "theorem:valid#kind@entity:theorem.\n" ++
  "theorem:valid#requires_assumption@assumption:finite.\n" ++
  "theorem:valid#requires_lemma@lemma:closure.\n" ++
  "theorem:valid#ensures@guarantee:sound.\n" ++
  "theorem:valid#criticality@value:high.\n" ++
  "theorem:valid#proof_token@proof:valid.\n" ++
  "theorem:unconditional#kind@entity:theorem.\n" ++
  "theorem:unconditional#unconditional@value:true.\n" ++
  "theorem:unconditional#ensures@guarantee:identity.\n" ++
  "theorem:vacuous#kind@entity:theorem.\n" ++
  "theorem:vacuous#ensures@guarantee:empty.\n" ++
  "theorem:missingLemma#kind@entity:theorem.\n" ++
  "theorem:missingLemma#requires_lemma@lemma:missing.\n" ++
  "theorem:missingLemma#ensures@guarantee:partial.\n" ++
  "theorem:noEvidence#kind@entity:theorem.\n" ++
  "theorem:noEvidence#requires_assumption@assumption:finite.\n" ++
  "theorem:noEvidence#ensures@guarantee:critical.\n" ++
  "theorem:noEvidence#criticality@value:critical.\n" ++
  "claim:supported#kind@entity:claim.\n" ++
  "claim:supported#supported_by@document:paper.\n" ++
  "claim:supported#supported_by@experiment:run.\n" ++
  "claim:supported#supported_by@theorem:valid.\n" ++
  "claim:unsupported#kind@entity:claim.\n" ++
  "claim:badProof#kind@entity:claim.\n" ++
  "claim:badProof#supported_by@document:paper.\n" ++
  "claim:badProof#proved_claim@value:true.\n" ++
  "claim:unknownSupport#kind@entity:claim.\n" ++
  "claim:unknownSupport#supported_by@artifact:unknown.\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          !report.ok && report.theorems.size == 5 && report.claims.size == 4 &&
          report.theoremFailures == 3 && report.claimFailures == 3
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          match report.theorems.find? (fun theorem => theorem.theorem == `theorem.valid) with
          | some theorem =>
              theorem.ok && theorem.nonvacuous && !theorem.unconditional &&
              theorem.assumptions == #[`assumption.finite] &&
              theorem.lemmas == #[`lemma.closure] &&
              theorem.guarantees == #[`guarantee.sound] &&
              theorem.proofEvidence == #[`proof.valid]
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          match report.theorems.find? (fun theorem => theorem.theorem == `theorem.unconditional) with
          | some theorem => theorem.ok && theorem.unconditional && theorem.nonvacuous
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          let vacuous := report.theorems.find? (fun theorem => theorem.theorem == `theorem.vacuous)
          let missing := report.theorems.find? (fun theorem => theorem.theorem == `theorem.missingLemma)
          let evidence := report.theorems.find? (fun theorem => theorem.theorem == `theorem.noEvidence)
          match vacuous, missing, evidence with
          | some v, some m, some e =>
              v.issues == #["vacuous-contract"] &&
              m.issues == #["missing-lemma:lemma.missing"] &&
              e.issues == #["proof-evidence-missing"]
          | _, _, _ => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          match report.claims.find? (fun claim => claim.claim == `claim.supported) with
          | some claim =>
              claim.ok && claim.supports.map (·.class) ==
                #[.documentary, .empirical, .kernel]
          | none => false
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          let unsupported := report.claims.find? (fun claim => claim.claim == `claim.unsupported)
          let bad := report.claims.find? (fun claim => claim.claim == `claim.badProof)
          let unknown := report.claims.find? (fun claim => claim.claim == `claim.unknownSupport)
          match unsupported, bad, unknown with
          | some u, some b, some k =>
              u.issues == #["support-missing"] &&
              b.assertedProved && b.issues == #["external-claim-proof-boundary"] &&
              k.issues == #["support-kind-missing:artifact.unknown"]
          | _, _, _ => false
      | .error _ => false
  | .error _ => false

private def passingSource : String :=
  "MODULE theorem.passing.\n" ++
  "assumption:a#kind@entity:assumption.\n" ++
  "proof:t#kind@entity:proof.\n" ++
  "document:d#kind@entity:document.\n" ++
  "theorem:t#kind@entity:theorem.\n" ++
  "theorem:t#requires_assumption@assumption:a.\n" ++
  "theorem:t#ensures@guarantee:g.\n" ++
  "theorem:t#criticality@value:high.\n" ++
  "theorem:t#proof_token@proof:t.\n" ++
  "claim:c#kind@entity:claim.\n" ++
  "claim:c#supported_by@document:d.\n"

#guard match Zil.Parser.DeclarationProgram.parseText passingSource with
  | .ok program =>
      match audit program with
      | .ok report => report.ok && report.theoremFailures == 0 && report.claimFailures == 0
      | .error _ => false
  | .error _ => false

run_cmd do
  match parsed with
  | .error error => throwError error
  | .ok program =>
      match audit program with
      | .error error => throwError error
      | .ok report =>
          let text := render report
          unless text.startsWith "ZIL-THEOREM-AUDIT\t1\n" do
            throwError "theorem audit report header is missing"
          unless hasSubstring text "theorem\ttheorem.vacuous\tfail" &&
                 hasSubstring text "vacuous-contract" do
            throwError "theorem audit lost vacuity evidence"
          unless hasSubstring text "claim\tclaim.badProof\tfail\tasserted-proved" &&
                 hasSubstring text "external-claim-proof-boundary" do
            throwError "theorem audit lost the external claim boundary"
