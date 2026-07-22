(ns zil.relational-ir-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.core :as core]
            [zil.relational-ir :as ir]))

(deftest relation-name-normalization-test
  (testing "snake case and Lean-style camel case normalize identically"
    (is (= :zil/requiresClaim (ir/canonical-relation :requires_claim)))
    (is (= :zil/requiresClaim (ir/canonical-relation :requiresClaim)))
    (is (= :zil/supportedBy (ir/canonical-relation "supported_by"))))
  (testing "already qualified profile relations preserve their namespace"
    (is (= :physics/formalizes
           (ir/canonical-relation :physics/formalizes)))))

(deftest legacy-and-native-equivalence-test
  (let [legacy (-> "?declaration#formalizes@?claim"
                   core/parse-atom
                   ir/from-legacy-atom)
        native (ir/from-native-map
                {:subject "?declaration"
                 :relation :formalizes
                 :object "?claim"
                 :source {:frontend :lean}})]
    (is (ir/equivalent? legacy native))
    (is (= {:term/kind :var :term/name "declaration"}
           (:subject legacy)))
    (is (= :zil/formalizes (:relation legacy)))))

(deftest legacy-rule-and-lean-native-rule-share-ir-test
  (let [formalizes (ir/from-legacy-atom
                    (core/parse-atom "?declaration#formalizes@?claim"))
        requires (ir/from-legacy-atom
                  (core/parse-atom "?declaration#requires@?requirement"))
        requires-claim-legacy
        (ir/from-legacy-atom
         (core/parse-atom "?claim#requires_claim@?requirement"))
        requires-claim-native
        (ir/from-native-map
         {:subject "?claim"
          :relation :requiresClaim
          :object "?requirement"})
        legacy-rule
        (ir/canonical-rule
         {:name 'schwarzschildClaimRequirement
          :variables ["claim" "requirement" "declaration"]
          :premises [formalizes requires]
          :conclusion requires-claim-legacy})
        native-rule
        (ir/canonical-rule
         {:name 'schwarzschildClaimRequirement
          :variables ["claim" "requirement" "declaration"]
          :premises [(ir/from-native-map
                      {:subject "?declaration"
                       :relation :formalizes
                       :object "?claim"})
                     (ir/from-native-map
                      {:subject "?declaration"
                       :relation :requires
                       :object "?requirement"})]
          :conclusion requires-claim-native})]
    (is (= (dissoc legacy-rule :source)
           (dissoc native-rule :source)))))

(deftest provenance-does-not-change-semantic-equivalence-test
  (let [a (ir/relation-expr "lean:Demo.t" :formalizes "claim:x"
                            {:frontend :embedded :line 10})
        b (ir/relation-expr "lean:Demo.t" :formalizes "claim:x"
                            {:frontend :lean-native :line 42})]
    (is (ir/equivalent? a b))))

(deftest invalid-ir-input-test
  (is (thrown-with-msg?
       clojure.lang.ExceptionInfo
       #"Legacy atom is missing"
       (ir/from-legacy-atom {:object "x" :relation :r})))
  (is (thrown-with-msg?
       clojure.lang.ExceptionInfo
       #"Native relation map is incomplete"
       (ir/from-native-map {:subject "x" :relation :r})))
  (is (thrown-with-msg?
       clojure.lang.ExceptionInfo
       #"Rule requires"
       (ir/canonical-rule {:name "bad" :premises []}))))
