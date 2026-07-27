(ns zil.bridge-lean-delta-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.lean-delta :as delta]
            [zil.runtime.datascript :as runtime]))

(defn event [dependency]
  {"operation" "linkLeanDecl"
   "declaration" "Demo.answer"
   "module" "Demo"
   "kind" "theorem"
   "kernel_present" true
   "trust" "kernel_checked_term"
   "uses_sorry" false
   "proved_claim" false
   "type_fingerprint" "lean-hash:1"
   "dependencies" [dependency]})

(defn batch [events]
  {"format" "zil.lean-events.v0.1"
   "profile" "lean-declarations-v0.1"
   "complete" true
   "lean_version" "4.32.0"
   "module" "Demo"
   "event_count" (count events)
   "events" events})

(deftest deterministic-content-addressed-delta-test
  (let [before (batch [(event "Nat")])
        after (batch [(event "Int")])
        a (delta/diff-batches before after)
        b (delta/diff-batches before after)]
    (is (= a b))
    (is (= (delta/batch-revision before) (get a "base_revision")))
    (is (= (delta/batch-revision after) (get a "revision")))
    ;; Only the changed dependency edge is invalidated and replaced.
    (is (= 2 (get a "operation_count")))
    (is (= ["retract" "assert"] (mapv #(get % "op") (get a "operations"))))))

(deftest delta-replay-applies-retractions-at-new-revision-test
  (let [before (batch [(event "Nat")])
        after (batch [(event "Int")])
        initial (delta/diff-batches nil before)
        changed (delta/diff-batches before after)
        conn (runtime/make-conn)]
    (runtime/transact-facts! conn (delta/delta->versioned-facts initial 1))
    (runtime/transact-facts! conn (delta/delta->versioned-facts changed 2))
    (let [facts (runtime/facts-at-or-before @conn 2)
          dependencies (filter #(= :depends_on (:relation %)) facts)]
      (is (= ["lean:Int"] (mapv :subject dependencies)))
      (is (not-any? #(= "lean:Nat" (:subject %)) facts)))))

(deftest removed-declaration-invalidates-all-its-facts-test
  (let [before (batch [(event "Nat")])
        after (batch [])
        removed (delta/diff-batches before after)]
    (is (pos? (get removed "operation_count")))
    (is (every? #(= "retract" (get % "op")) (get removed "operations")))
    (is (every? #(= "declaration_removed" (get % "cause"))
                (get removed "operations")))))
