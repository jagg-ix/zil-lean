(ns zil.bridge-proof-token-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.proof-token :as proof-token]))

(defn- event
  ([declaration]
   (event declaration {}))
  ([declaration overrides]
   (merge
    {"operation" "linkLeanDecl"
     "declaration" declaration
     "module" "Demo"
     "kind" "theorem"
     "kernel_present" true
     "trust" "kernel_checked_term"
     "uses_sorry" false
     "proved_claim" false
     "type_fingerprint" (str "lean-hash:" declaration)
     "dependencies" ["Nat"]}
    overrides)))

(defn- event-batch [events]
  {"format" "zil.lean-events.v0.1"
   "profile" "lean-declarations-v0.1"
   "complete" true
   "lean_version" "4.32.0"
   "module" "Demo"
   "event_count" (count events)
   "events" (vec events)})

(defn- token
  ([id declaration]
   (token id declaration {}))
  ([id declaration overrides]
   (merge
    {"token_id" id
     "declaration" declaration
     "expected_kind" "theorem"}
    overrides)))

(defn- token-batch [tokens]
  {"format" proof-token/token-format
   "complete" true
   "module" "Demo"
   "token_count" (count tokens)
   "tokens" (vec tokens)})

(deftest resolves-kernel-checked-declaration-test
  (let [tokens (token-batch [(token "proof:answer" "Demo.answer"
                                    {"claim" "answer-is-correct"})])
        events (event-batch [(event "Demo.answer")])
        report (proof-token/resolve-batches tokens events)
        resolution (first (:resolutions report))]
    (is (:ok report))
    (is (= 1 (:resolved report)))
    (is (= 0 (:unresolved report)))
    (is (= :resolved (:status resolution)))
    (is (= "lean-hash:Demo.answer" (:type_fingerprint resolution)))
    (is (= :external_unproved (:claim_status resolution)))
    (is (= ["Nat"] (:dependencies resolution)))
    (is (.startsWith (:event_batch_fingerprint report) "sha256:"))
    (is (.startsWith (:token_batch_fingerprint report) "sha256:"))))

(deftest deterministic-fingerprints-ignore-map-order-test
  (let [left (event-batch [(event "Demo.answer")])
        right (into {} (reverse (seq left)))]
    (is (= (proof-token/batch-fingerprint left)
           (proof-token/batch-fingerprint right)))))

(deftest classifies-all-resolution-failures-test
  (let [tokens (token-batch
                [(token "proof:missing" "Demo.missing")
                 (token "proof:ambiguous" "Demo.duplicate")
                 (token "proof:module" "Other.answer")
                 (token "proof:kind" "Demo.definition")
                 (token "proof:kernel" "Demo.noKernel")
                 (token "proof:sorry" "Demo.sorry")
                 (token "proof:trust" "Demo.asserted")
                 (token "proof:fingerprint" "Demo.noFingerprint")])
        events (event-batch
                [(event "Demo.duplicate")
                 (event "Demo.duplicate")
                 (event "Other.answer" {"module" "Other"})
                 (event "Demo.definition" {"kind" "def"})
                 (event "Demo.noKernel" {"kernel_present" false})
                 (event "Demo.sorry" {"uses_sorry" true})
                 (event "Demo.asserted" {"trust" "asserted"})
                 (event "Demo.noFingerprint" {"type_fingerprint" ""})])
        report (proof-token/resolve-batches tokens events)
        statuses (into {} (map (juxt :token_id :status) (:resolutions report)))]
    (is (false? (:ok report)))
    (is (= 0 (:resolved report)))
    (is (= :missing (statuses "proof:missing")))
    (is (= :ambiguous (statuses "proof:ambiguous")))
    (is (= :module_mismatch (statuses "proof:module")))
    (is (= :kind_mismatch (statuses "proof:kind")))
    (is (= :kernel_missing (statuses "proof:kernel")))
    (is (= :uses_sorry (statuses "proof:sorry")))
    (is (= :trust_mismatch (statuses "proof:trust")))
    (is (= :fingerprint_missing (statuses "proof:fingerprint")))))

(deftest accepts-explicit-trust-policy-test
  (let [tokens (token-batch
                [(token "proof:custom" "Demo.answer"
                        {"acceptable_trust" ["reviewed_kernel_term"]})])
        events (event-batch
                [(event "Demo.answer" {"trust" "reviewed_kernel_term"})])]
    (is (:ok (proof-token/resolve-batches tokens events)))))

(deftest rejects-invalid-token-batches-test
  (testing "partial batch"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"Partial proof token batches"
         (proof-token/validate-token-batch!
          (assoc (token-batch []) "complete" false)))))
  (testing "duplicate token IDs"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"IDs must be unique"
         (proof-token/validate-token-batch!
          (token-batch [(token "proof:same" "Demo.a")
                        (token "proof:same" "Demo.b")])))))
  (testing "count mismatch"
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"token_count"
         (proof-token/validate-token-batch!
          (assoc (token-batch []) "token_count" 1))))))

(deftest rejects-cross-module-batches-test
  (let [tokens (token-batch [(token "proof:answer" "Demo.answer")])
        events (assoc (event-batch [(event "Demo.answer")]) "module" "Other")]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"different modules"
         (proof-token/resolve-batches tokens events)))))

(deftest writes-deterministic-resolution-report-test
  (let [tokens-file (java.io.File/createTempFile "zil-proof-tokens-" ".json")
        events-file (java.io.File/createTempFile "zil-proof-events-" ".json")
        output-file (java.io.File/createTempFile "zil-proof-resolution-" ".json")
        tokens (token-batch [(token "proof:answer" "Demo.answer")])
        events (event-batch [(event "Demo.answer")])]
    (spit tokens-file (json/write-str tokens))
    (spit events-file (json/write-str events))
    (let [report (proof-token/write-resolution!
                  (.getPath tokens-file) (.getPath events-file) (.getPath output-file))
          decoded (json/read-str (slurp output-file))]
      (is (:ok report))
      (is (= proof-token/resolution-format (get decoded "format")))
      (is (= 1 (get decoded "resolved")))
      (is (= "resolved" (get-in decoded ["resolutions" 0 "status"])))
      (is (= 1 (count (get decoded "resolutions")))))))
