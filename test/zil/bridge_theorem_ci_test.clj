(ns zil.bridge-theorem-ci-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.theorem-ci :as btci]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-bridge-theorem-ci"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest theorem-ci-one-shot-pipeline-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "incident-theorem.zc")
        out-dir (java.io.File. root "artifacts")]
    (spit model-file "MODULE theorem.ci.demo.
theorem:t_incident_guard#kind@entity:theorem.
theorem:t_incident_guard#criticality@value:medium.
theorem:t_incident_guard#requires_assumption@assumption:a_operator_present.
theorem:t_incident_guard#ensures@guarantee:incident_guard_active.
")
    (let [report (btci/run-theorem-ci
                  (.getAbsolutePath model-file)
                  {:out-dir (.getAbsolutePath out-dir)
                   :bridge-module "theorem.ci.bridge"
                   :tla-module "TheoremCIBridge"
                   :lean-namespace "Zil.Generated.Theorem.CI"})
          bridge-zc (get-in report [:artifacts :bridge_zc])
          bridge-tla (get-in report [:artifacts :bridge_tla])
          bridge-lean (get-in report [:artifacts :bridge_lean])]
      (is (:ok report))
      (is (= 1 (get-in report [:bridge :theorem_count])))
      (is (= true (get-in report [:checks :query_ci :ok])))
      (is (= true (get-in report [:checks :lts :ok])))
      (is (= true (get-in report [:checks :constraint :ok])))
      (is (.exists (java.io.File. bridge-zc)))
      (is (.exists (java.io.File. bridge-tla)))
      (is (.exists (java.io.File. bridge-lean)))
      (is (re-find #"criticality=medium" (slurp bridge-zc)))
      (is (re-find #"MODULE TheoremCIBridge" (slurp bridge-tla)))
      (is (re-find #"namespace Zil.Generated.Theorem.Ci" (slurp bridge-lean))))))

(deftest theorem-ci-fails-when-query-ci-fails-test
  (let [root (tmp-dir)
        model-file (java.io.File. root "incident-theorem-query-fail.zc")
        out-dir (java.io.File. root "artifacts")]
    (spit model-file "MODULE theorem.ci.query.fail.
theorem:t_incident_guard#kind@entity:theorem.
QUERY_PACK ops_pack [queries=[q_must], must_return=[q_must]].
DSL_PROFILE ops [query_pack=ops_pack].
QUERY q_must:
FIND ?x WHERE ?x#kind@entity:nonexistent.
")
    (try
      (btci/run-theorem-ci
       (.getAbsolutePath model-file)
       {:out-dir (.getAbsolutePath out-dir)})
      (is false "Expected theorem-ci to fail due to query-ci must_return violation")
      (catch clojure.lang.ExceptionInfo e
        (is (= :query-ci (:stage (ex-data e))))
        (is (false? (get-in (ex-data e) [:report :ok])))))))
