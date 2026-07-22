(ns zil.relation-profile-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.relation-profile :as profile]
            [zil.relational-ir :as ir]))

(def variable-kinds
  {"declaration" :declaration
   "claim" :claim
   "requirement" :requirement
   "source" :evidence-source})

(deftest research-profile-relation-validation-test
  (testing "valid variable endpoint combinations"
    (is (profile/validates-relation?
         profile/research-profile
         variable-kinds
         (ir/from-native-map
          {:subject "?declaration"
           :relation :formalizes
           :object "?claim"})))
    (is (profile/validates-relation?
         profile/research-profile
         variable-kinds
         (ir/from-native-map
          {:subject "?claim"
           :relation :requiresClaim
           :object "?requirement"}))))
  (testing "category errors are rejected"
    (is (false?
         (profile/validates-relation?
          profile/research-profile
          variable-kinds
          (ir/from-native-map
           {:subject "?declaration"
            :relation :formalizes
            :object "?requirement"})))))
  (testing "ground prefixes match the Lean profile"
    (is (profile/validates-relation?
         profile/research-profile
         {}
         (ir/from-native-map
          {:subject "lean.Schwarzschild.metric"
           :relation :formalizes
           :object "claim.schwarzschildMetric"})))
    (is (false?
         (profile/validates-relation?
          profile/research-profile
          {}
          (ir/from-native-map
           {:subject "paper.schwarzschild1916"
            :relation :formalizes
            :object "claim.schwarzschildMetric"}))))))

(deftest research-profile-rule-validation-test
  (let [rule
        (ir/canonical-rule
         {:name 'schwarzschildClaimRequirement
          :variables ["claim" "requirement" "declaration"]
          :premises
          [(ir/from-native-map
            {:subject "?declaration" :relation :formalizes :object "?claim"})
           (ir/from-native-map
            {:subject "?declaration" :relation :requires :object "?requirement"})]
          :conclusion
          (ir/from-native-map
           {:subject "?claim" :relation :requiresClaim :object "?requirement"})})]
    (is (profile/validates-rule? profile/research-profile variable-kinds rule))))
