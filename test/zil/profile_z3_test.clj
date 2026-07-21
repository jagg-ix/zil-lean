(ns zil.profile-z3-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.profile.z3 :as z3]))

(deftest parse-condition-supports-implies-operator-test
  (testing "Keyword form: IMPLIES"
    (let [ast (z3/parse-condition "x > 0 IMPLIES y > 0")]
      (is (= :op (:kind ast)))
      (is (= :implies (:op ast)))))

  (testing "Symbolic forms: -> and =>"
    (is (= :implies (:op (z3/parse-condition "x > 0 -> y > 0"))))
    (is (= :implies (:op (z3/parse-condition "x > 0 => y > 0"))))))

(deftest parse-condition-implies-is-right-associative-test
  (let [ast (z3/parse-condition "a IMPLIES b IMPLIES c")]
    (is (= :implies (:op ast)))
    (is (= :implies (:op (second (:args ast)))))))

(deftest compile-conditions-emits-smt-implies-test
  (let [{:keys [script]} (z3/compile-conditions ["x > 0 IMPLIES y > 0"])]
    (is (re-find #"\(=> " script))))

(deftest compile-conditions-supports-logic-override-test
  (let [{:keys [script logic]} (z3/compile-conditions ["x > 0"] {:logic :qf_lra})]
    (is (= "QF_LRA" logic))
    (is (re-find #"\(set-logic QF_LRA\)" script))))
