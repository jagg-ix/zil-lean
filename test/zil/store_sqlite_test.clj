(ns zil.store-sqlite-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.bridge.lean-delta :as delta]
            [zil.store.sqlite :as store]))

(defn- temp-path [suffix]
  (.getAbsolutePath (java.io.File/createTempFile "zil-store-" suffix)))

(defn- event [dependency]
  {"operation" "linkLeanDecl" "declaration" "Demo.answer" "module" "Demo"
   "kind" "theorem" "kernel_present" true "trust" "kernel_checked_term"
   "uses_sorry" false "proved_claim" false "type_fingerprint" "lean-hash:1"
   "dependencies" [dependency]})

(defn- batch [dependency]
  {"format" "zil.lean-events.v0.1" "profile" "lean-declarations-v0.1"
   "complete" true "lean_version" "4.32.0" "module" "Demo"
   "event_count" 1 "events" [(event dependency)]})

(defn- write-json! [path value]
  (spit path (json/write-str value)) path)

(deftest transactional-publication-replay-and-conflict-test
  (let [db (temp-path ".sqlite")
        before (batch "Nat") after (batch "Int")
        initial (delta/diff-batches nil before)
        changed (delta/diff-batches before after)
        initial-path (write-json! (temp-path ".json") initial)
        changed-path (write-json! (temp-path ".json") changed)]
    (is (:ok (store/publish-delta! db initial-path)))
    (is (= (get initial "revision")
           (with-open [conn (store/initialize! (store/connect db))]
             (store/current-revision conn "Demo"))))
    ;; Stale initial publication rolls back and preserves last-known-good.
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"revision conflict"
                          (store/publish-delta! db initial-path)))
    (is (:ok (store/publish-delta! db changed-path)))
    (let [report (store/verify-store db "Demo")]
      (is (:ok report))
      (is (= (get changed "revision") (:revision report)))
      (is (= (:stored_fact_count report) (:replayed_fact_count report))))))

(deftest failed-trust-validation-preserves-current-pointer-test
  (let [db (temp-path ".sqlite") before (batch "Nat")
        initial (delta/diff-batches nil before)
        initial-path (write-json! (temp-path ".json") initial)]
    (store/publish-delta! db initial-path)
    (let [bad (-> initial
                  (assoc "base_revision" (get initial "revision"))
                  (assoc "revision" (str "sha256:" (apply str (repeat 64 "f"))))
                  (assoc "operation_count" 1)
                  (assoc "operations" [{"op" "assert" "cause" "declaration_changed"
                                         "declaration" "Demo.answer"
                                         "fact" {"object" "claim:x" "relation" "proved_claim"
                                                 "subject" "value:true"}}]))
          bad-path (write-json! (temp-path ".json") bad)]
      (is (thrown-with-msg? clojure.lang.ExceptionInfo #"promote"
                            (store/publish-delta! db bad-path)))
      (with-open [conn (store/initialize! (store/connect db))]
        (is (= (get initial "revision") (store/current-revision conn "Demo")))))))
