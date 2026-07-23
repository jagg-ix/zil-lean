import Zil.ProofObligation
import Zil.Parser.DeclarationProgram

open Zil.ProofObligation

private def hasSubstring (text needle : String) : Bool :=
  (text.splitOn needle).length > 1

private def source : String :=
  "MODULE proof.governance.\n" ++
  "service:api#ready@value:true.\n" ++
  "PROOF_OBLIGATION lean_ready [relation=ready, statement=\"Lean theorem checks readiness\", tool=lean4, status=proved, proof_token=proof:ready, criticality=high].\n" ++
  "PROOF_OBLIGATION acl2_ready [relation=ready, statement=\"ACL2 log checks readiness\", tool=acl2, status=proved, artifact_in=proof.log, criticality=medium].\n" ++
  "PROOF_OBLIGATION pending_z3 [relation=ready, statement=\"Z3 result is pending\", tool=z3, status=pending, logic=qf_lia, expectation=sat].\n" ++
  "PROOF_OBLIGATION failed_manual [relation=ready, statement=\"Manual review failed\", tool=manual, status=failed, evidence=review:failed].\n" ++
  "PROOF_OBLIGATION waived_low [relation=ready, statement=\"Low risk exception\", tool=manual, status=waived, waiver_reason=\"accepted debt\", criticality=low].\n" ++
  "PROOF_OBLIGATION waived_critical [relation=ready, statement=\"Critical exception\", tool=manual, status=waived, waiver_reason=\"temporary\", criticality=critical].\n" ++
  "PROOF_OBLIGATION unknown_relation [relation=missing_relation, statement=\"Unknown relation\", tool=lean4, status=proved, proof_token=proof:missing].\n"

private def parsed : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program => .ok program
  | .error error => .error error.render

#guard match parsed with
  | .ok program =>
      match audit program with
      | .ok report =>
          !report.ok && report.results.size == 7 &&
          report.satisfied == 2 && report.violated == 1 &&
          report.blocked == 3 && report.waived == 1
      | .error _ => false
  | .error _ => false

#guard match parsed with
  | .ok program =>
      match audit program (some .lean4) with
      | .ok report =>
          !report.ok && report.results.size == 2 &&
          report.satisfied == 1 && report.blocked == 1 &&
          match report.results.find? (fun result =>
            result.obligation.id == `proof_obligation.unknown_relation) with
          | some result => result.reasons == #["unknown-relation"]
          | none => false
      | .error _ => false
  | .error _ => false

private def passingSource : String :=
  "MODULE proof.passing.\n" ++
  "service:api#ready@value:true.\n" ++
  "PROOF_OBLIGATION lean_ready [relation=ready, statement=\"Lean evidence\", tool=lean4, status=proved, proof_token=proof:ready].\n" ++
  "PROOF_OBLIGATION external_ready [relation=ready, statement=\"External artifact\", tool=z3, status=proved, artifact_in=z3.log].\n" ++
  "PROOF_OBLIGATION waived_low [relation=ready, statement=\"Accepted exception\", tool=manual, status=waived, waiver_reason=\"documented\", criticality=low].\n"

#guard match Zil.Parser.DeclarationProgram.parseText passingSource with
  | .ok program =>
      match audit program with
      | .ok report => report.ok && report.satisfied == 2 && report.waived == 1
      | .error _ => false
  | .error _ => false

private def provedWithoutEvidence : String :=
  "MODULE proof.noEvidence.\n" ++
  "service:api#ready@value:true.\n" ++
  "PROOF_OBLIGATION bad [relation=ready, statement=\"No evidence\", tool=lean4, status=proved].\n"

#guard match Zil.Parser.DeclarationProgram.parseText provedWithoutEvidence with
  | .ok program =>
      match audit program with
      | .ok report =>
          !report.ok && report.blocked == 1 &&
          report.results[0]!.reasons == #["proved-status-requires-evidence"]
      | .error _ => false
  | .error _ => false

private def emptySource : String :=
  "MODULE proof.empty.\n" ++
  "service:api#ready@value:true.\n"

#guard match Zil.Parser.DeclarationProgram.parseText emptySource with
  | .ok program =>
      match audit program with
      | .ok report => report.ok && report.results.isEmpty
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
          unless text.startsWith "ZIL-PROOF-OBLIGATIONS\t1\n" do
            throwError "proof obligation report header is missing"
          unless hasSubstring text "obligation\tproof_obligation.pending_z3" &&
                 hasSubstring text "backend-unavailable-without-evidence" do
            throwError "proof obligation report lost unavailable backend evidence"
          unless hasSubstring text "critical-obligation-cannot-be-waived" do
            throwError "proof obligation report lost the critical waiver failure"
