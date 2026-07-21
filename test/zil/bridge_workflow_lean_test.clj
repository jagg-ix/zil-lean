(ns zil.bridge-workflow-lean-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.bridge.lean-delta :as delta]
            [zil.bridge.workflow-lean :as workflow]
            [zil.safety.action :as safety]
            [zil.store.sqlite :as store]))

(defn- temp-path [suffix]
  (.getAbsolutePath (java.io.File/createTempFile "zil-workflow-" suffix)))

(def event
  {"operation" "linkLeanDecl" "declaration" "Demo.answer" "module" "Demo"
   "kind" "theorem" "kernel_present" true "trust" "kernel_checked_term"
   "uses_sorry" false "proved_claim" false "type_fingerprint" "lean-hash:1"
   "dependencies" ["Nat"]})

(deftest frozen-workflow-module-contains-verified-evidence-test
  (let [db (temp-path ".sqlite")
        batch {"format" "zil.lean-events.v0.1" "profile" "lean-declarations-v0.1"
               "complete" true "lean_version" "4.32.0" "module" "Demo"
               "event_count" 1 "events" [event]}
        delta (delta/diff-batches nil batch) revision (get delta "revision")
        delta-path (temp-path ".json") output (temp-path ".lean")]
    (spit delta-path (json/write-str delta))
    (store/publish-delta! db delta-path)
    (safety/grant-scope! db "agent:a" "src/demo")
    (safety/acquire-lease! db {:lease-id "lease:1" :agent-id "agent:a" :module "Demo"
                               :scope "src/demo" :base-revision revision :now 100 :ttl-seconds 100})
    (safety/create-checkpoint! db {:checkpoint-id "checkpoint:1" :module "Demo"
                                   :revision revision :agent-id "agent:a"})
    (safety/record-action! db {"action_id" "action:1" "agent_id" "agent:a"
                               "module" "Demo" "base_revision" revision "scope" "src/demo"
                               "lease_id" "lease:1" "checkpoint_id" "checkpoint:1" "now" 150
                               "preconditions_pass" true
                               "rollback" {"kind" "rollback" "reference" "git:abc"}})
    (let [report (workflow/export-workflow! db "Demo" output "Zil.Generated.WorkflowDemo" 150)
          text (slurp output)]
      (is (:ok report))
      (is (= 1 (:action_count report)))
      (is (re-find #"module\s+public import Zil.Workflow" text))
      (is (re-find #"def snapshot : Snapshot" text))
      (is (re-find #"contextFresh := true" text))
      (is (re-find #"example : MayExecute" text)))))
