(ns zil.exchange-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.exchange :as exchange]
            [zil.relational-ir :as ir]))

(def formalizes
  (ir/relation-expr "lean.Exchange.theorem" :formalizes "claim.exchange"))

(def requirement-rule
  (ir/canonical-rule
   {:name "exchangeRequirement"
    :variables ["declaration" "claim" "requirement"]
    :premises [(ir/relation-expr "?declaration" :formalizes "?claim")
               (ir/relation-expr "?declaration" :requires "?requirement")]
    :conclusion (ir/relation-expr "?claim" :requires-claim "?requirement")
    :trust :graph-derived}))

(def envelope
  {:schema-version "1"
   :knowledge-revision 17
   :profile-name "zil.profile.research"
   :profile-version "0.1"
   :facts [formalizes]
   :rules [requirement-rule]})

(deftest revisioned-envelope-round-trip
  (is (exchange/round-trips? envelope))
  (let [decoded (exchange/decode-envelope (exchange/encode-envelope envelope))]
    (is (= 17 (:knowledge-revision decoded)))
    (is (= "0.1" (:profile-version decoded)))
    (is (= :zil/requiresClaim
           (get-in decoded [:rules 0 :rule/conclusion :relation])))))

(deftest malformed-envelope-is-rejected
  (testing "invalid headers"
    (is (thrown? clojure.lang.ExceptionInfo
                 (exchange/decode-envelope "BAD\t1\nrevision\t0\nprofile\t-\t-"))))
  (testing "unknown rows"
    (is (thrown? clojure.lang.ExceptionInfo
                 (exchange/decode-envelope
                  "ZILX\t1\nrevision\t0\nprofile\t-\t-\nunknown\tvalue"))))))