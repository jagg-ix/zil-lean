(ns zil.bridge-theorem-lock-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.proof-token :as proof-token]
            [zil.bridge.theorem-lock :as theorem-lock]))

(defn- resolved-row
  ([token-id declaration fingerprint]
   (resolved-row token-id declaration fingerprint {}))
  ([token-id declaration fingerprint overrides]
   (merge
    {:token_id token-id
     :declaration declaration
     :status :resolved
     :module "Demo"
     :kind "theorem"
     :trust "kernel_checked_term"
     :kernel_present true
     :uses_sorry false
     :type_fingerprint fingerprint
     :dependencies ["Nat"]}
    overrides)))

(defn- resolution [rows]
  {:format proof-token/resolution-format
   :ok (every? #(= :resolved (:status %)) rows)
   :module "Demo"
   :lean_version "4.32.0"
   :event_batch_fingerprint "sha256:events"
   :token_batch_fingerprint "sha256:tokens"
   :token_count (count rows)
   :resolved (count (filter #(= :resolved (:status %)) rows))
   :unresolved (count (remove #(= :resolved (:status %)) rows))
   :resolutions (vec rows)})

(def base-resolution
  (resolution [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")
               (resolved-row "proof:b" "Demo.b" "lean-hash:b-v1")]))

(deftest creates-deterministic-locks-from-resolved-tokens-test
  (let [locks (theorem-lock/create-locks base-resolution)]
    (is (= theorem-lock/lock-format (:format locks)))
    (is (:complete locks))
    (is (:strict locks))
    (is (= 2 (:lock_count locks)))
    (is (= ["proof:a" "proof:b"] (mapv :token_id (:locks locks))))
    (is (= "lean-hash:a-v1" (get-in locks [:locks 0 :type_fingerprint])))
    (is (.startsWith (:document_fingerprint locks) "sha256:"))
    (is (= locks (theorem-lock/create-locks base-resolution)))))

(deftest unchanged-lock-check-passes-test
  (let [locks (theorem-lock/create-locks base-resolution)
        report (theorem-lock/check-locks locks base-resolution)]
    (is (:ok report))
    (is (= 2 (:unchanged report)))
    (is (= 0 (:changed report)))
    (is (every? #(= :unchanged (:status %)) (:results report)))))

(deftest detects-fingerprint-drift-test
  (let [locks (theorem-lock/create-locks base-resolution)
        current (resolution
                 [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v2")
                  (resolved-row "proof:b" "Demo.b" "lean-hash:b-v1")])
        report (theorem-lock/check-locks locks current)
        changed (first (filter #(= :fingerprint_changed (:status %))
                               (:results report)))]
    (is (false? (:ok report)))
    (is (= 1 (:changed report)))
    (is (= "lean-hash:a-v1" (:locked_type_fingerprint changed)))
    (is (= "lean-hash:a-v2" (:current_type_fingerprint changed)))))

(deftest detects-identity-and-kind-drift-test
  (let [locks (theorem-lock/create-locks base-resolution)
        current (resolution
                 [(resolved-row "proof:a" "Demo.renamed" "lean-hash:a-v1")
                  (resolved-row "proof:b" "Demo.b" "lean-hash:b-v1"
                                {:kind "def"})])
        report (theorem-lock/check-locks locks current)
        statuses (set (map :status (:results report)))]
    (is (false? (:ok report)))
    (is (contains? statuses :declaration_changed))
    (is (contains? statuses :kind_changed))))

(deftest detects-row-and-report-module-drift-test
  (let [locks (theorem-lock/create-locks base-resolution)
        row-drift (resolution
                   [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v1"
                                  {:module "Other"})
                    (resolved-row "proof:b" "Demo.b" "lean-hash:b-v1")])
        row-report (theorem-lock/check-locks locks row-drift)
        report-drift (assoc base-resolution :module "Other")
        module-report (theorem-lock/check-locks locks report-drift)]
    (is (some #(= :module_changed (:status %)) (:results row-report)))
    (is (false? (:ok module-report)))
    (is (= 1 (:changed module-report)))
    (is (= :resolution_module_changed
           (get-in module-report [:failures 0 :kind])))))

(deftest detects-missing-and-unresolved-current-tokens-test
  (let [locks (theorem-lock/create-locks base-resolution)
        current (resolution
                 [(assoc (resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")
                         :status :kernel_missing)])
        report (theorem-lock/check-locks locks current)
        statuses (into {} (map (juxt :token_id :status) (:results report)))]
    (is (false? (:ok report)))
    (is (= :current_unresolved (statuses "proof:a")))
    (is (= :missing_token (statuses "proof:b")))))

(deftest strict-locks-reject-unexpected-tokens-test
  (let [locks (theorem-lock/create-locks
               (resolution [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")]))
        report (theorem-lock/check-locks locks base-resolution)]
    (is (false? (:ok report)))
    (is (some #(and (= "proof:b" (:token_id %))
                    (= :unexpected_token (:status %)))
              (:results report)))))

(deftest extensible-locks-allow-additional-tokens-test
  (let [locks (theorem-lock/create-locks
               (resolution [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")])
               {:strict false})
        report (theorem-lock/check-locks locks base-resolution)]
    (is (:ok report))
    (is (some #(= :additional_allowed (:status %)) (:results report)))))

(deftest rejects-unresolved-or-duplicate-baseline-test
  (let [unresolved (resolution
                    [(assoc (resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")
                            :status :uses_sorry)])
        duplicate (resolution
                   [(resolved-row "proof:a" "Demo.a" "lean-hash:a-v1")
                    (resolved-row "proof:b" "Demo.a" "lean-hash:a-v1")])]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"fully resolved"
         (theorem-lock/create-locks unresolved)))
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"declarations must be unique"
         (theorem-lock/create-locks duplicate)))))

(deftest rejects-invalid-lock-documents-test
  (let [locks (theorem-lock/create-locks base-resolution)]
    (testing "partial lock file"
      (is (thrown-with-msg?
           clojure.lang.ExceptionInfo
           #"Partial theorem lock files"
           (theorem-lock/validate-locks! (assoc locks :complete false)))))
    (testing "duplicate declarations"
      (let [duplicate (assoc-in locks [:locks 1 :declaration] "Demo.a")]
        (is (thrown-with-msg?
             clojure.lang.ExceptionInfo
             #"declarations must be unique"
             (theorem-lock/validate-locks! duplicate)))))
    (testing "row module differs"
      (let [wrong-module (assoc-in locks [:locks 0 :module] "Other")]
        (is (thrown-with-msg?
             clojure.lang.ExceptionInfo
             #"row module differs"
             (theorem-lock/validate-locks! wrong-module)))))
    (testing "document was modified"
      (let [tampered (assoc locks :strict false)]
        (is (thrown-with-msg?
             clojure.lang.ExceptionInfo
             #"fingerprint mismatch"
             (theorem-lock/validate-locks! tampered)))))))

(deftest rejects-malformed-current-resolution-test
  (let [locks (theorem-lock/create-locks base-resolution)
        malformed (assoc-in base-resolution [:resolutions 0 :status] :invented)]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"Unknown proof token resolution status"
         (theorem-lock/check-locks locks malformed)))))

(deftest file-round-trip-and-check-report-test
  (let [resolution-file (java.io.File/createTempFile "zil-lock-resolution-" ".json")
        locks-file (java.io.File/createTempFile "zil-locks-" ".json")
        report-file (java.io.File/createTempFile "zil-lock-report-" ".json")]
    (spit resolution-file (json/write-str base-resolution))
    (theorem-lock/create-lock-file! (.getPath resolution-file)
                                    (.getPath locks-file))
    (let [report (theorem-lock/check-lock-file!
                  (.getPath locks-file)
                  (.getPath resolution-file)
                  (.getPath report-file))
          decoded (json/read-str (slurp report-file))]
      (is (:ok report))
      (is (= theorem-lock/check-format (get decoded "format")))
      (is (= 2 (get decoded "unchanged"))))))
