(ns zil.bridge-vstack-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.vstack :as bv]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-vstack"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest vstack-bridge-from-refinement-relations-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "vstack-model.zc")
        out-file (java.io.File. root "generated/vstack-bridge.zc")]
    (spit model-file "MODULE vstack.bridge.demo.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
CORRESPONDS logic_to_runtime [left=lean4:StepFn, right=acl2:ExecStep, refines=core_to_logic].
PROOF_OBLIGATION po_refines_sound [relation=core_to_logic, statement=\"next-state preserves invariant\", tool=z3, criticality=high].
")
    (let [report (bv/refinement-contracts->bridge
                  (.getAbsolutePath model-file)
                  {:output-path (.getAbsolutePath out-file)
                   :module-name "vstack.bridge.generated"})
          text (:text report)]
      (is (:ok report))
      (is (= 1 (:refines_count report)))
      (is (= 1 (:corresponds_count report)))
      (is (= 1 (:proof_obligation_count report)))
      (is (.exists out-file))
      (is (re-find #"MODULE vstack\.bridge\.generated\." text))
      (is (re-find #"LTS_ATOM refines_core_to_logic_flow" text))
      (is (re-find #"LTS_ATOM corresponds_logic_to_runtime_flow" text))
      (is (re-find #"POLICY proof_obligation_po_refines_sound_soundness" text)))))
