(ns zil.control-plane-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.control.adapters :as adapters]
            [zil.control.capability :as capability]
            [zil.control.command :as command]
            [zil.control.runtime :as runtime]
            [zil.worker.pool :as worker-pool]))

(deftest repository-capability-inventory-is-complete
  (let [inventory (capability/load-valid-inventory)]
    (is (= :lean (:authority (capability/operation-capability inventory "compile"))))
    (is (= :compile-v1 (:id (capability/operation-capability inventory "compile"))))
    (is (= :conformance-v1
           (:id (capability/operation-capability inventory "conformance"))))
    (is (= 8 (count (capability/operation-index inventory))))))

(deftest command-table-is-derived-from-authoritative-inventory
  (let [inventory (capability/load-valid-inventory)
        commands (command/command-table inventory)]
    (is (= #{"parse" "compile" "expand" "conformance" "query"
             "authorize" "impact" "recovery-audit"}
           (set (keys commands))))
    (is (= "compile-v1" (get-in commands ["compile" :capability])))
    (is (false? (get-in commands ["compile" :replaceable])))))

(deftest runtime-keeps-semantic-failure-distinct-from-transport
  (let [inventory (capability/load-valid-inventory)
        control-plane (runtime/->ControlPlane :fake-pool inventory (atom false) {})
        response {:schema "ZIL-EXCHANGE/1"
                  :request_id "request:test"
                  :operation "authorize"
                  :status "invalid"
                  :authority "lean"
                  :assurance ""
                  :errors ["invalid authorization request"]}]
    (with-redefs [worker-pool/invoke! (fn [_ _ _] response)]
      (is (= response
             (runtime/invoke! control-plane
                              {:operation "authorize"
                               :input-path "model.zc"
                               :arguments ["doc:x" "viewer" "user:y"]}
                              10)))
      (is (thrown-with-msg? clojure.lang.ExceptionInfo
                            #"Lean-authoritative operation failed"
                            (runtime/payload! response))))))

(deftest adapter-runner-preserves-operation-and-namespace
  (let [inventory (capability/load-valid-inventory)
        control-plane (runtime/->ControlPlane :fake-pool inventory (atom false) {})
        calls (atom [])]
    (with-redefs [command/execute!
                  (fn [_ operation input-path arguments]
                    (swap! calls conj [operation input-path arguments])
                    {:status "ok" :payload "import Zil\n"})]
      (let [runner (adapters/request-runner control-plane)
            result (runner {:command [adapters/adapter-command
                                      "compile" "/tmp/model.zc" "-"
                                      "Project.Generated.Model"]})]
        (is (= 0 (:exit result)))
        (is (= "import Zil\n" (:out result)))
        (is (= [["compile" "/tmp/model.zc" ["Project.Generated.Model"]]]
               @calls))))))

(deftest adapter-rejects-nonsemantic-process-commands
  (let [inventory (capability/load-valid-inventory)
        control-plane (runtime/->ControlPlane :fake-pool inventory (atom false) {})]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"nonsemantic command"
         ((adapters/request-runner control-plane)
          {:command ["lake" "env" "lean" "Generated.lean"]})))))
