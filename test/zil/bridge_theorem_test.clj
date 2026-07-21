(ns zil.bridge-theorem-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.theorem :as bth]
            [zil.core :as core]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-theorem"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest theorem-bridge-from-direct-contracts-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "contracts.zc")]
    (spit model-file "MODULE theorem.contract.demo.
theorem:t_storage_consistency#kind@entity:theorem.
theorem:t_storage_consistency#criticality@value:high.
theorem:t_storage_consistency#requires_assumption@assumption:a_etcd_quorum.
theorem:t_storage_consistency#requires_lemma@lemma:l_etcd_election_safety.
theorem:t_storage_consistency#ensures@guarantee:storage_consistency.
theorem:t_playbook_conformance#kind@entity:theorem.
theorem:t_playbook_conformance#criticality@value:medium.
theorem:t_playbook_conformance#requires_assumption@assumption:a_manual_audit_review_done.
")
    (let [report (bth/theorem-contracts->bridge (.getAbsolutePath model-file))
          text (:text report)
          compiled (core/compile-program text)]
      (is (:ok report))
      (is (= 2 (:theorem_count report)))
      (is (re-find #"MODULE theorem\.contract\.demo\.theorem\.bridge\." text))
      (is (re-find #"LTS_ATOM theorem_t_storage_consistency_flow" text))
      (is (re-find #"POLICY theorem_t_storage_consistency_requirements" text))
      (is (re-find #"assumption_a_etcd_quorum_holds" text))
      (is (re-find #"lemma_l_etcd_election_safety_proved" text))
      (is (re-find #"criticality=medium" text))
      (is (= "theorem.contract.demo.theorem.bridge" (:module report)))
      (is (seq (:declarations compiled))))))

(deftest theorem-bridge-falls-back-to-preprocess-for-macros-test
  (let [root (tmp-dir)
        lib-dir (java.io.File. root "lib")
        models-dir (java.io.File. root "models")
        _ (.mkdirs lib-dir)
        _ (.mkdirs models-dir)
        macro-file (java.io.File. lib-dir "thm.zc")
        model-file (java.io.File. models-dir "macro-contracts.zc")
        out-file (java.io.File. root "generated/theorem-bridge.zc")]
    (spit macro-file "MODULE theorem.impact.lib.
MACRO THM_THEOREM(id, criticality):
EMIT theorem:{{id}}#kind@entity:theorem.
EMIT theorem:{{id}}#criticality@value:{{criticality}}.
ENDMACRO.
")
    (spit model-file "MODULE theorem.macro.demo.
USE THM_THEOREM(t_from_macro, high).
")
    (let [report (bth/theorem-contracts->bridge (.getAbsolutePath model-file)
                                                {:module-name "Bridge.From.Macros"
                                                 :output-path (.getAbsolutePath out-file)})
          content (slurp out-file)]
      (is (:ok report))
      (is (= 1 (:theorem_count report)))
      (is (= "Bridge.From.Macros" (:module report)))
      (is (= (.getAbsolutePath out-file) (:output_path report)))
      (is (.exists out-file))
      (is (re-find #"MODULE Bridge\.From\.Macros\." content))
      (is (re-find #"LTS_ATOM theorem_t_from_macro_flow" content))
      (is (re-find #"POLICY theorem_t_from_macro_proof_soundness" content))
      (is (seq (:declarations (core/compile-program content)))))))
