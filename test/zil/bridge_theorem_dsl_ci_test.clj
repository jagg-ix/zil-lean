(ns zil.bridge-theorem-dsl-ci-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.theorem-dsl-ci :as btdsl]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-theorem-dsl-ci"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest theorem-dsl-ci-one-shot-pipeline-test
  (let [out-root (tmp-dir)
        report (btdsl/run-theorem-dsl-ci
                "examples/theorem-dsl-incident.zc"
                {:out-dir (.getAbsolutePath out-root)})
        summary-json (get-in report [:artifacts :summary_json])]
    (is (:ok report))
    (is (.exists (java.io.File. (get-in report [:artifacts :preprocessed_zc]))))
    (is (.exists (java.io.File. (get-in report [:artifacts :bridge_zc]))))
    (is (.exists (java.io.File. (get-in report [:artifacts :bridge_tla]))))
    (is (.exists (java.io.File. (get-in report [:artifacts :bridge_lean]))))
    (is (.exists (java.io.File. summary-json)))
    (is (seq (get-in report [:operator_summary :statuses])))
    (is (>= (get-in report [:operator_summary :status_counts "BROKEN"] 0) 1))
    (is (>= (get-in report [:operator_summary :status_counts "WEAK"] 0) 1))
    (is (seq (get-in report [:operator_summary :break_roots])))
    (is (seq (get-in report [:operator_summary :impact_set])))
    (let [json-text (slurp summary-json)]
      (is (re-find #"\"operator_summary\"" json-text))
      (is (re-find #"\"status_counts\"" json-text))
      (is (re-find #"\"break_roots\"" json-text))
      (is (re-find #"\"impact_set\"" json-text)))))
