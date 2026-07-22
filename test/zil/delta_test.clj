(ns zil.delta-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.delta :as delta]
            [zil.relational-ir :as ir]))

(def old-fact (ir/relation-expr "lean.Delta.old" :formalizes "claim.old"))
(def new-fact (ir/relation-expr "lean.Delta.new" :formalizes "claim.new"))

(def snapshot
  {:schema-version "1"
   :knowledge-revision 5
   :facts [old-fact]
   :rules []})

(def change
  {:base-revision 5
   :target-revision 6
   :remove-facts [old-fact]
   :add-facts [new-fact]
   :add-rules []
   :remove-rules []})

(deftest apply-and-round-trip-delta
  (let [updated (delta/apply-delta snapshot change)
        decoded (delta/decode-delta (delta/encode-delta change))]
    (is (= 6 (:knowledge-revision updated)))
    (is (= [new-fact] (:facts updated)))
    (is (= 5 (:base-revision decoded)))
    (is (= 6 (:target-revision decoded)))
    (is (= 1 (count (:add-facts decoded))))))

(deftest stale-and-invalid-deltas-are-rejected
  (testing "stale base revision"
    (is (thrown? clojure.lang.ExceptionInfo
                 (delta/apply-delta snapshot (assoc change :base-revision 4)))))
  (testing "non-increasing target"
    (is (thrown? clojure.lang.ExceptionInfo
                 (delta/apply-delta snapshot (assoc change :target-revision 5)))))
  (testing "missing removals"
    (is (thrown? clojure.lang.ExceptionInfo
                 (delta/apply-delta snapshot
                                    (assoc change :remove-facts
                                           [(ir/relation-expr "missing" :formalizes "claim")]))))))