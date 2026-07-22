(ns zil.test-runner
  (:require [clojure.test :refer [run-tests]]
            [zil.bridge-lean4-test]
            [zil.bridge-lean-events-test]
            [zil.bridge-lean-delta-test]
            [zil.bridge-snapshot-test]
            [zil.bridge-workflow-lean-test]
            [zil.bridge-souffle-test]
            [zil.bridge-theorem-ci-test]
            [zil.bridge-theorem-dsl-ci-test]
            [zil.bridge-theorem-test]
            [zil.bridge-proof-obligation-test]
            [zil.bridge-vstack-ci-test]
            [zil.bridge-vstack-test]
            [zil.bridge-tla-test]
            [zil.core-test]
            [zil.embedded-test]
            [zil.exchange-test]
            [zil.import-hcl-test]
            [zil.interop-test]
            [zil.lower-test]
            [zil.model-exchange-test]
            [zil.preprocess-test]
            [zil.profile-z3-test]
            [zil.relational-ir-test]
            [zil.relation-profile-test]
            [zil.runtime-datascript-vector-clock-test]
            [zil.runtime-ingest-test]
            [zil.recovery-drift-test]
            [zil.formalization-target-test]
            [zil.safety-action-test]
            [zil.safety-token-action-test]
            [zil.store-sqlite-test]))

(defn -main
  [& _]
  (let [{:keys [fail error]} (run-tests 'zil.bridge-lean4-test
                                         'zil.bridge-lean-events-test
                                         'zil.bridge-lean-delta-test
                                         'zil.bridge-snapshot-test
                                         'zil.bridge-workflow-lean-test
                                         'zil.bridge-souffle-test
                                         'zil.bridge-theorem-ci-test
                                         'zil.bridge-theorem-dsl-ci-test
                                         'zil.bridge-theorem-test
                                         'zil.bridge-proof-obligation-test
                                         'zil.bridge-vstack-ci-test
                                         'zil.bridge-vstack-test
                                         'zil.bridge-tla-test
                                         'zil.core-test
                                         'zil.embedded-test
                                         'zil.exchange-test
                                         'zil.import-hcl-test
                                         'zil.interop-test
                                         'zil.lower-test
                                         'zil.model-exchange-test
                                         'zil.preprocess-test
                                         'zil.profile-z3-test
                                         'zil.relational-ir-test
                                         'zil.relation-profile-test
                                         'zil.runtime-datascript-vector-clock-test
                                         'zil.runtime-ingest-test
                                         'zil.recovery-drift-test
                                         'zil.formalization-target-test
                                         'zil.safety-action-test
                                         'zil.safety-token-action-test
                                         'zil.store-sqlite-test)]
    (System/exit (if (pos? (+ fail error)) 1 0))))