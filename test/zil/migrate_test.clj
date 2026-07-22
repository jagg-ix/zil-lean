(ns zil.migrate-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.exchange :as exchange]
            [zil.migrate :as migrate]))

(def lossless-source
  "MODULE migration.demo.\n\
lean.Theorem#formalizes@claim.demo.\n\
lean.Theorem#requires@requirement.demo.\n\
RULE transfer:\n\
IF ?declaration#formalizes@?claim AND ?declaration#requires@?requirement\n\
THEN ?claim#requires_claim@?requirement.\n")

(deftest lossless-zc-to-zilx-migration
  (let [{:keys [envelope report]} (migrate/migrate-text lossless-source)
        decoded (exchange/decode-envelope (exchange/encode-envelope envelope))]
    (is (:lossless? report))
    (is (= 2 (count (:facts decoded))))
    (is (= 1 (count (:rules decoded))))
    (is (= :zil/requiresClaim
           (get-in decoded [:rules 0 :rule/conclusion :relation])))
    (is (= ["declaration" "claim" "requirement"]
           (get-in decoded [:rules 0 :rule/variables])))))

(deftest strict-migration-rejects-loss
  (testing "attributes have no canonical ZILX representation"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"lossy"
         (migrate/migrate-text
          "thing#status@active [confidence=0.9]."))))
  (testing "legacy persisted queries are reported instead of silently dropped"
    (is (thrown? clojure.lang.ExceptionInfo
                 (migrate/migrate-text
                  "QUERY q:\nFIND ?x WHERE ?x#status@active.")))))

(deftest lossy-mode-emits-audit-report
  (let [{:keys [envelope report]}
        (migrate/migrate-text
         "thing#status@active [confidence=0.9]."
         {:strict? false})]
    (is (false? (:lossless? report)))
    (is (= :dropped-attributes (get-in report [:issues 0 :kind])))
    (is (= 1 (count (:facts envelope))))))
