(ns zil.safety-token-action-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.lean-delta :as delta]
            [zil.safety.action :as safety]
            [zil.store.sqlite :as store]))

(defn- temp-path [suffix]
  (.getAbsolutePath (java.io.File/createTempFile "zil-token-safety-" suffix)))

(def batch
  {"format" "zil.lean-events.v0.1" "profile" "lean-declarations-v0.1"
   "complete" true "lean_version" "4.32.0" "module" "Demo" "event_count" 1
   "events" [{"operation" "linkLeanDecl" "declaration" "Demo.answer" "module" "Demo"
              "kind" "theorem" "kernel_present" true "trust" "kernel_checked_term"
              "uses_sorry" false "proved_claim" false "type_fingerprint" "lean-hash:1"
              "dependencies" ["Nat"]}]})

(defn- setup []
  (let [db (temp-path ".sqlite") change (delta/diff-batches nil batch)
        path (temp-path ".json") revision (get change "revision")]
    (spit path (json/write-str change))
    (store/publish-delta! db path)
    (safety/grant-scope! db "agent:a" "src/demo")
    (safety/acquire-lease! db {:lease-id "lease:1" :agent-id "agent:a" :module "Demo"
                               :scope "src/demo" :base-revision revision :now 100 :ttl-seconds 100})
    {:db db :revision revision}))

(defn- token-request [revision]
  {"token_id" "acttok:1" "task_id" "task:demo" "agent_id" "agent:a"
   "module" "Demo" "base_revision" revision "scope" "src/demo"
   "lease_id" "lease:1" "context_bundle_id" "ctx:1" "now" 120 "ttl_seconds" 60
   "action" {"type" "modify_file" "target" "file:Demo.lean"
             "expected_effects" ["compile"] "required_postconditions" ["file_compiles"]}
   "rollback" {"kind" "rollback" "reference" "git:abc"}
   "evidence" {"context_fresh" true "context_complete" true
               "no_critical_conflict" true "authorized" true "valid_lease" true
               "preconditions_pass" true "recovery_available" true}})

(deftest token-checkpoint-action-order-is-enforced-test
  (let [{:keys [db revision]} (setup)
        issued (safety/issue-action-token! db (token-request revision))]
    (is (:allowed issued))
    (testing "execution cannot precede a token-bound checkpoint"
      (is (thrown-with-msg? clojure.lang.ExceptionInfo #"matching checkpoint"
                            (safety/record-token-action!
                             db {"action_id" "action:early" "action_token" "acttok:1"
                                 "checkpoint_id" "checkpoint:1" "now" 130
                                 "observed_outputs" []}))))
    (is (:ok (safety/create-token-checkpoint!
              db {"checkpoint_id" "checkpoint:1" "action_token" "acttok:1"
                  "agent_id" "agent:a" "now" 130})))
    (let [recorded (safety/record-token-action!
                    db {"action_id" "action:1" "action_token" "acttok:1"
                        "checkpoint_id" "checkpoint:1" "now" 140
                        "observed_outputs" [{"artifact" "file:Demo.lean"
                                             "hash" (str "sha256:" (apply str (repeat 64 "a")))}]})]
      (is (= :recorded (:status recorded)))
      (is (= 1 (:observed_output_count recorded))))
    (testing "a consumed token cannot execute twice"
      (is (thrown? clojure.lang.ExceptionInfo
                   (safety/record-token-action!
                    db {"action_id" "action:2" "action_token" "acttok:1"
                        "checkpoint_id" "checkpoint:1" "now" 150
                        "observed_outputs" []}))))))

(deftest missing-context-evidence-denies-without-token-test
  (let [{:keys [db revision]} (setup)
        request (assoc-in (token-request revision) ["evidence" "context_complete"] false)
        result (safety/issue-action-token! db request)]
    (is (false? (:allowed result)))
    (is (some #{:context-complete} (:failures result)))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Unknown action token"
                          (safety/create-token-checkpoint!
                           db {"checkpoint_id" "checkpoint:denied"
                               "action_token" "acttok:1" "agent_id" "agent:a" "now" 130})))))
