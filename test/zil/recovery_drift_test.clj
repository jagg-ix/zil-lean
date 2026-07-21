(ns zil.recovery-drift-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.bridge.lean-delta :as delta]
            [zil.recovery.drift :as drift]
            [zil.store.sqlite :as store]))

(defn- temp-path [suffix]
  (.getAbsolutePath (java.io.File/createTempFile "zil-drift-" suffix)))

(defn- event [name fingerprint dependencies]
  {"operation" "linkLeanDecl" "declaration" name "module" "Demo"
   "kind" "theorem" "kernel_present" true "trust" "kernel_checked_term"
   "uses_sorry" false "proved_claim" false "type_fingerprint" fingerprint
   "dependencies" dependencies})

(defn- batch [answer-fingerprint]
  (let [events [(event "Demo.answer" answer-fingerprint ["Nat"])
                (event "Demo.consumer" "lean-hash:2" ["Demo.answer"])]]
    {"format" "zil.lean-events.v0.1" "profile" "lean-declarations-v0.1"
     "complete" true "lean_version" "4.32.0" "module" "Demo"
     "event_count" (count events) "events" events}))

(defn- write-json! [value]
  (let [path (temp-path ".json")] (spit path (json/write-str value)) path))

(deftest stale-context-produces-bounded-recovery-plan-test
  (let [db (temp-path ".sqlite") before (batch "lean-hash:1")
        after (batch "lean-hash:3") initial (delta/diff-batches nil before)
        changed (delta/diff-batches before after)]
    (store/publish-delta! db (write-json! initial))
    (store/publish-delta! db (write-json! changed))
    (let [report (drift/analyze-drift db "Demo" (get initial "revision"))]
      (is (= :stale (:status report)))
      (is (= :context-stale (:code report)))
      (is (= ["Demo.answer"] (:changed_declarations report)))
      (is (= ["lean:Demo.consumer"] (:affected_dependents report)))
      (is (:complete report))
      (is (= :run_preflight (-> report :recovery_plan last :action))))
    (is (false? (:allowed (drift/mutation-preflight db "Demo" (get initial "revision")))))
    (is (true? (:allowed (drift/mutation-preflight db "Demo" (get changed "revision")))))))

(deftest impact-traversal-reports-bounds-test
  (let [db (temp-path ".sqlite") before (batch "lean-hash:1")
        after (batch "lean-hash:3") initial (delta/diff-batches nil before)
        changed (delta/diff-batches before after)]
    (store/publish-delta! db (write-json! initial))
    (store/publish-delta! db (write-json! changed))
    (let [report (drift/analyze-drift db "Demo" (get initial "revision")
                                      {:max-depth 0 :max-nodes 10})]
      (is (false? (:complete report)))
      (is (= 0 (:impact_depth report))))))
