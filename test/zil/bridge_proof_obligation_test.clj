(ns zil.bridge-proof-obligation-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.bridge.proof-obligation :as bpo]
            [zil.profile.z3 :as z3]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-proof-obligation"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- with-z3
  [f]
  (if (z3/z3-available?)
    (f)
    (is true "z3 unavailable; skipping proof-obligation z3 assertions")))

(deftest proof-obligation-check-z3-tool-test
  (with-z3
   (fn []
     (let [root (tmp-dir)
           model-file (java.io.File. root "proof-obligation-model.zc")]
       (spit model-file "MODULE proof.ob.demo.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
PROOF_OBLIGATION po_sat [relation=core_to_logic, statement=\"x > 0\", tool=z3, logic=QF_LRA, expectation=sat, criticality=high].
PROOF_OBLIGATION po_unsat [relation=core_to_logic, statement=\"x > 0 AND x < 0\", tool=z3, logic=QF_LRA, expectation=unsat, criticality=medium].
")
       (let [report (bpo/run-proof-obligation-check
                     (.getAbsolutePath model-file)
                     {:tool :z3})]
         (is (:ok report))
         (is (= :z3 (get report :tool_filter)))
         (is (= 2 (get report :obligation_count)))
         (is (= 2 (get report :evaluated_count)))
         (is (= 2 (get-in report [:status_counts :satisfied] 0)))
         (is (= 0 (get-in report [:status_counts :violated] 0))))))))

(deftest proof-obligation-check-z3-violation-test
  (with-z3
   (fn []
     (let [root (tmp-dir)
           model-file (java.io.File. root "proof-obligation-violation.zc")]
       (spit model-file "MODULE proof.ob.violation.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
PROOF_OBLIGATION po_bad_expect [relation=core_to_logic, statement=\"x > 0\", tool=z3, logic=QF_LRA, expectation=unsat, criticality=high].
")
       (let [report (bpo/run-proof-obligation-check
                     (.getAbsolutePath model-file)
                     {:tool "z3"})]
         (is (false? (:ok report)))
         (is (= 1 (get report :obligation_count)))
         (is (= 1 (get-in report [:status_counts :violated] 0))))))))

(deftest proof-obligation-check-skips-unsupported-tools-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "proof-obligation-skip.zc")]
    (spit model-file "MODULE proof.ob.skip.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
PROOF_OBLIGATION po_lean [relation=core_to_logic, statement=\"placeholder\", tool=lean4, criticality=medium].
")
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {})]
      (is (:ok report))
      (is (= 0 (get report :evaluated_count)))
      (is (= 1 (get-in report [:status_counts :skipped] 0)))
      (is (= :all (get report :tool_filter))))))

(deftest proof-obligation-check-acl2-artifact-success-test
  (let [root (tmp-dir)
        log-file (java.io.File. root "acl2-success.log")
        model-file (java.io.File. root "proof-obligation-acl2-ok.zc")]
    (spit log-file "ACL2 proves theorem. Q.E.D.")
    (spit model-file
          (str "MODULE proof.ob.acl2.ok.\n"
               "REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].\n"
               "PROOF_OBLIGATION po_acl2_ok [relation=core_to_logic, statement=\"dummy\", tool=acl2, artifact_in=\""
               (.getAbsolutePath log-file)
               "\", expectation=sat, criticality=high].\n"))
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {:tool :acl2})
          row (first (:obligations report))]
      (is (:ok report))
      (is (= 1 (:evaluated_count report)))
      (is (= 1 (get-in report [:status_counts :satisfied] 0)))
      (is (= :acl2 (:backend row)))
      (is (= :proved (:solver_status row)))
      (is (= :satisfied (:status row))))))

(deftest proof-obligation-check-acl2-artifact-failure-test
  (let [root (tmp-dir)
        log-file (java.io.File. root "acl2-failure.log")
        model-file (java.io.File. root "proof-obligation-acl2-fail.zc")]
    (spit log-file "HARD ACL2 ERROR in theorem admission.")
    (spit model-file
          (str "MODULE proof.ob.acl2.fail.\n"
               "REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].\n"
               "PROOF_OBLIGATION po_acl2_fail [relation=core_to_logic, statement=\"dummy\", tool=acl2, artifact_in=\""
               (.getAbsolutePath log-file)
               "\", expectation=sat, criticality=high].\n"))
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {:tool :acl2})
          row (first (:obligations report))]
      (is (false? (:ok report)))
      (is (= 1 (:evaluated_count report)))
      (is (= 1 (get-in report [:status_counts :violated] 0)))
      (is (= :acl2 (:backend row)))
      (is (= :failed (:solver_status row)))
      (is (= :violated (:status row))))))

(deftest proof-obligation-check-macro-only-fallback-test
  (let [root (tmp-dir)
        lib-dir (doto (java.io.File. root "lib") .mkdirs)
        lib-file (java.io.File. lib-dir "macro-plus-rules.zc")
        log-file (java.io.File. root "acl2-macro.log")
        model-file (java.io.File. root "proof-obligation-acl2-macro.zc")]
    (spit log-file "Q.E.D.")
    (spit lib-file
          "MODULE local.lib.
MACRO LOCAL_ACL2_OB(id, relation, artifact):
EMIT PROOF_OBLIGATION {{id}} [relation={{relation}}, statement=\"from macro\", tool=acl2, artifact_in={{artifact}}, expectation=sat, criticality=high].
ENDMACRO.
RULE bad_negative_cycle:
IF ?x#rel@?y AND NOT ?y#rel@?x
THEN ?x#rel@?y.
")
    (spit model-file
          (str "MODULE proof.ob.acl2.macro.\n"
               "REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].\n"
               "USE LOCAL_ACL2_OB(po_acl2_macro, core_to_logic, \"" (.getAbsolutePath log-file) "\").\n"))
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {:tool :acl2})]
      (is (:ok report))
      (is (= 1 (:obligation_count report)))
      (is (= 1 (:evaluated_count report)))
      (is (= 1 (get-in report [:status_counts :satisfied] 0))))))

(deftest proof-obligation-check-acl2-command-success-test
  (let [root (tmp-dir)
        log-out (java.io.File. root "acl2-command.log")
        model-file (java.io.File. root "proof-obligation-acl2-command-ok.zc")]
    (spit model-file
          (str "MODULE proof.ob.acl2.command.ok.\n"
               "REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].\n"
               "PROOF_OBLIGATION po_acl2_cmd_ok [relation=core_to_logic, statement=\"dummy\", tool=acl2, command=\"printf 'Q.E.D.'\", artifact_out=\"" (.getAbsolutePath log-out) "\", expectation=sat, criticality=high].\n"))
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {:tool :acl2})
          row (first (:obligations report))]
      (is (:ok report))
      (is (= 1 (:evaluated_count report)))
      (is (= 1 (get-in report [:status_counts :satisfied] 0)))
      (is (= :command (:mode row)))
      (is (= :proved (:solver_status row)))
      (is (.exists log-out))
      (is (re-find #"Q\.E\.D\." (slurp log-out))))))

(deftest proof-obligation-check-acl2-command-failure-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "proof-obligation-acl2-command-fail.zc")]
    (spit model-file
          "MODULE proof.ob.acl2.command.fail.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
PROOF_OBLIGATION po_acl2_cmd_fail [relation=core_to_logic, statement=\"dummy\", tool=acl2, command=\"printf 'HARD ACL2 ERROR'; exit 1\", expectation=sat, criticality=high].
")
    (let [report (bpo/run-proof-obligation-check
                  (.getAbsolutePath model-file)
                  {:tool :acl2})
          row (first (:obligations report))]
      (is (false? (:ok report)))
      (is (= 1 (:evaluated_count report)))
      (is (= 1 (get-in report [:status_counts :violated] 0)))
      (is (= :command (:mode row)))
      (is (= :failed (:solver_status row)))
      (is (= :violated (:status row))))))
