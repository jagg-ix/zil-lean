(ns zil.safety-action-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.bridge.lean-delta :as delta]
            [zil.safety.action :as safety]
            [zil.store.sqlite :as store]))

(defn- temp-path [suffix]
  (.getAbsolutePath (java.io.File/createTempFile "zil-safety-" suffix)))

(def event
  {"operation" "linkLeanDecl" "declaration" "Demo.answer" "module" "Demo"
   "kind" "theorem" "kernel_present" true "trust" "kernel_checked_term"
   "uses_sorry" false "proved_claim" false "type_fingerprint" "lean-hash:1"
   "dependencies" ["Nat"]})

(def batch
  {"format" "zil.lean-events.v0.1" "profile" "lean-declarations-v0.1"
   "complete" true "lean_version" "4.32.0" "module" "Demo"
   "event_count" 1 "events" [event]})

(defn- setup []
  (let [db (temp-path ".sqlite") delta (delta/diff-batches nil batch)
        path (temp-path ".json") revision (get delta "revision")]
    (spit path (json/write-str delta))
    (store/publish-delta! db path)
    (safety/grant-scope! db "agent:a" "src/demo")
    (safety/acquire-lease! db {:lease-id "lease:1" :agent-id "agent:a" :module "Demo"
                               :scope "src/demo" :base-revision revision :now 100 :ttl-seconds 100})
    (safety/create-checkpoint! db {:checkpoint-id "checkpoint:1" :module "Demo"
                                   :revision revision :agent-id "agent:a"})
    {:db db :revision revision}))

(defn- request [revision]
  {"action_id" "action:1" "agent_id" "agent:a" "module" "Demo"
   "base_revision" revision "scope" "src/demo" "lease_id" "lease:1"
   "checkpoint_id" "checkpoint:1" "now" 150 "preconditions_pass" true
   "rollback" {"kind" "rollback" "reference" "git:abc123"}})

(deftest full-safety-invariant-allows-and-audits-action-test
  (let [{:keys [db revision]} (setup) req (request revision)]
    (is (:allowed (safety/action-preflight db req)))
    (is (= :recorded (:status (safety/record-action! db req))))
    (is (= :verified (:status (safety/verify-postconditions! db "action:1" true))))))

(deftest missing-safety-components-deny-without-recording-test
  (let [{:keys [db revision]} (setup)
        req (assoc (request revision) "preconditions_pass" false "rollback" {})
        report (safety/action-preflight db req)]
    (is (false? (:allowed report)))
    (is (some #{:precondition-failed} (:failures report)))
    (is (some #{:missing-rollback} (:failures report)))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"preflight denied"
                          (safety/record-action! db req)))))

(deftest expired-lease-and-failed-postcondition-require-recovery-test
  (let [{:keys [db revision]} (setup)
        expired (assoc (request revision) "now" 201)]
    (is (some #{:invalid-lease} (:failures (safety/action-preflight db expired))))
    (safety/record-action! db (request revision))
    (let [result (safety/verify-postconditions! db "action:1" false)]
      (is (= :recovery-required (:status result)))
      (is (= :postcondition-failed (:code result))))))
