(ns zil.bridge-vstack-ci-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.core :as core]
            [zil.bridge.vstack-ci :as bvci]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-vstack-ci"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest vstack-ci-integrated-pipeline-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "vstack-ci-model.zc")
        out-dir (java.io.File. root "artifacts")]
    (spit model-file "MODULE vstack.ci.demo.
theorem:t_incident_guard#kind@entity:theorem.
theorem:t_incident_guard#criticality@value:medium.
theorem:t_incident_guard#requires_assumption@assumption:a_operator_present.
theorem:t_incident_guard#ensures@guarantee:incident_guard_active.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
PROOF_OBLIGATION po_refines_sound [relation=core_to_logic, statement=\"x > 0\", tool=z3, logic=QF_LRA, expectation=sat, criticality=high].
")
    (let [report (bvci/run-vstack-ci
                  (.getAbsolutePath model-file)
                  {:out-dir (.getAbsolutePath out-dir)
                   :bridge-module "vstack.ci.bridge"
                   :tla-module "VStackCIBridge"
                   :lean-namespace "Zil.Generated.VStack.CI"})
          theorem-zc (get-in report [:artifacts :theorem_bridge_zc])
          refinement-zc (get-in report [:artifacts :refinement_bridge_zc])
          bridge-tla (get-in report [:artifacts :bridge_tla])
          bridge-lean (get-in report [:artifacts :bridge_lean])
          feedback-zc (get-in report [:artifacts :formal_feedback_zc])
          summary-json (get-in report [:artifacts :summary_json])
          summary (json/read-str (slurp summary-json) :key-fn keyword)
          feedback-text (slurp feedback-zc)
          feedback-exec (core/execute-file feedback-zc)]
      (is (:ok report))
      (is (= true (get-in report [:proof_obligations :ok])))
      (is (= 1 (get-in report [:proof_obligations :evaluated_count])))
      (is (= true (get-in report [:checks :query_ci :ok])))
      (is (= true (get-in report [:checks :lts :ok])))
      (is (= true (get-in report [:checks :constraint :ok])))
      (is (= 1 (get-in report [:stages :theorem :theorem_count])))
      (is (= 1 (get-in report [:stages :refinement :refines_count])))
      (is (= 1 (get-in report [:stages :refinement :proof_obligation_count])))
      (is (.exists (java.io.File. theorem-zc)))
      (is (.exists (java.io.File. refinement-zc)))
      (is (.exists (java.io.File. bridge-tla)))
      (is (.exists (java.io.File. bridge-lean)))
      (is (.exists (java.io.File. feedback-zc)))
      (is (.exists (java.io.File. summary-json)))
      (is (= true (:ok summary)))
      (is (= true (get-in summary [:proof_obligations :ok])))
      (is (re-find #"entity:formal_feedback" feedback-text))
      (is (re-find #"entity:formal_obligation" feedback-text))
      (is (= "vstack-ci-model.vstack.feedback" (:module feedback-exec)))
      (is (re-find #"MODULE VStackCIBridge" (slurp bridge-tla)))
      (is (re-find #"namespace Zil.Generated.VStack.Ci" (slurp bridge-lean))))))
