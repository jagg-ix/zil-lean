(ns zil.worker-protocol-test
  (:require [clojure.test :refer [deftest is]]
            [zil.worker.client :as client]
            [zil.worker.pool :as pool]
            [zil.worker.protocol :as protocol])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files)
           (java.nio.file.attribute FileAttribute)))

(deftest canonical-request-validates
  (let [path (Files/createTempFile "zil-exchange-" ".zc" (make-array FileAttribute 0))]
    (try
      (Files/writeString path "MODULE exchange.test.\n" StandardCharsets/UTF_8
                         (into-array java.nio.file.OpenOption []))
      (let [request (client/request {:request-id "request:test"
                                     :operation "parse"
                                     :input-path (str path)})
            encoded (protocol/write-line request)]
        (is (= protocol/schema (get request "schema")))
        (is (= ["parse-v1"] (get request "capabilities")))
        (is (re-matches #"sha256:[0-9a-f]{64}" (get request "input_sha256")))
        (is (= request (protocol/validate-request! request)))
        (is (.startsWith encoded "{\"schema\":\"ZIL-EXCHANGE/1\",\"request_id\":")))
      (finally
        (Files/deleteIfExists path)))))

(deftest operations-fail-closed
  (let [base (protocol/canonical-request
              {:request-id "request:test"
               :operation "parse"
               :input-path "model.zc"
               :base-revision "-"
               :input-sha256 (str "sha256:" (apply str (repeat 64 "a")))
               :capabilities ["parse-v1"]
               :arguments []})]
    (is (thrown? Exception
                 (protocol/validate-request! (assoc base "operation" "shell"))))
    (is (thrown? Exception
                 (protocol/validate-request! (assoc base "capabilities" []))))
    (is (thrown? Exception
                 (protocol/validate-request! (assoc base "capabilities"
                                                    ["parse-v1" "parse-v1"]))))
    (is (thrown? Exception
                 (protocol/validate-request! (assoc base "arguments" ["extra"]))))))

(deftest response-attestation-preserves-semantic-fields
  (let [response {:schema protocol/schema
                  :request_id "request:test"
                  :protocol_version protocol/protocol-version
                  :operation "authorize"
                  :status "ok"
                  :authority "lean"
                  :assurance "validated"
                  :input_sha256 (str "sha256:" (apply str (repeat 64 "a")))
                  :payload "ZIL-AUTHORIZATION\t1\nstatus\tdeny\n"
                  :result_sha256 ""
                  :errors []
                  :warnings ["result-sha256-pending-client-attestation"]}
        attested (client/attest-response response)]
    (is (= "lean" (:authority attested)))
    (is (= "validated" (:assurance attested)))
    (is (= (:payload response) (:payload attested)))
    (is (re-matches #"sha256:[0-9a-f]{64}" (:result_sha256 attested)))
    (is (empty? (:warnings attested)))))

(deftest response-identity-is-checked
  (let [digest (str "sha256:" (apply str (repeat 64 "a")))
        request (protocol/canonical-request
                 {:request-id "request:test"
                  :operation "parse"
                  :input-path "model.zc"
                  :base-revision "-"
                  :input-sha256 digest
                  :capabilities ["parse-v1"]
                  :arguments []})
        response {:schema protocol/schema
                  :request_id "request:wrong"
                  :protocol_version protocol/protocol-version
                  :operation "parse"
                  :input_sha256 digest
                  :result_sha256 ""
                  :authority "lean"}]
    (is (thrown? Exception (protocol/validate-response! request response)))
    (is (thrown? Exception
                 (protocol/validate-response!
                  request
                  (assoc response :request_id "request:test"
                         :input_sha256 (str "sha256:" (apply str (repeat 64 "b")))))))
    (is (thrown? Exception
                 (protocol/validate-response!
                  request
                  (assoc response :request_id "request:test"
                         :result_sha256 digest))))))

(deftest bounded-pool-reuses-and-stops-workers
  (let [started (atom 0)
        stopped (atom [])
        invoked (atom [])]
    (with-redefs [client/start-worker!
                  (fn [_]
                    {:id (swap! started inc)
                     :alive (atom true)})
                  client/alive?
                  (fn [worker] @(:alive worker))
                  client/stop-worker!
                  (fn [worker]
                    (reset! (:alive worker) false)
                    (swap! stopped conj (:id worker))
                    {:exit 0})
                  client/invoke!
                  (fn [worker request]
                    (swap! invoked conj [(:id worker) request])
                    {:status "ok" :worker (:id worker)})]
      (let [workers (pool/start-pool! {:size 2})
            first-result (pool/invoke! workers {:request_id "request:1"} 100)
            second-result (pool/invoke! workers {:request_id "request:2"} 100)]
        (is (= 2 @started))
        (is (= "ok" (:status first-result)))
        (is (= "ok" (:status second-result)))
        (is (= 2 (count @invoked)))
        (is (= {:closed true :workers 2} (pool/stop-pool! workers)))
        (is (= #{1 2} (set @stopped)))
        (is (thrown? Exception (pool/acquire! workers 1)))))))
