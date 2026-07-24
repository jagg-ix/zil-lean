(ns zil.control-event-store-test
  (:require [clojure.test :refer [deftest is]]
            [zil.control.command :as command]
            [zil.control.durable :as durable]
            [zil.store.control-event :as store]
            [zil.worker.client :as worker-client])
  (:import (java.nio.file Files)
           (java.nio.file.attribute FileAttribute)))

(defn- temp-db []
  (str (Files/createTempFile "zil-control-events-" ".sqlite"
                             (make-array FileAttribute 0))))

(defn- decision [text]
  (worker-client/sha256-text text))

(deftest append-is-cas-bound-hash-chained-and-receipted
  (let [database (temp-db)
        stream "workflow:test"
        first-event {:stream stream
                     :event-type "context-generated"
                     :actor "agent:a"
                     :request-id "request:1"
                     :decision-sha256 (decision "context")
                     :payload {:workflow_id "workflow:1"}}
        second-event {:stream stream
                      :event-type "action-token-issued"
                      :actor "agent:a"
                      :request-id "request:2"
                      :decision-sha256 (decision "token")
                      :payload {:workflow_id "workflow:1"
                                :token_id "token:1"}}
        result (store/append-events! database stream 0 [first-event second-event])]
    (is (:ok result))
    (is (= 2 (get-in result [:receipt :event_count])))
    (is (= 2 (get-in result [:receipt :final_revision])))
    (is (= [1 2] (mapv :revision (store/read-events database stream))))
    (is (:ok (store/verify-stream database stream)))
    (is (:ok (store/verify-receipts database stream)))
    (is (:ok (store/verify-store database stream)))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"expected revision conflict"
                          (store/append-events! database stream 0 [first-event])))))

(deftest durable-invocation-records-valid-response-only
  (let [database (temp-db)
        stream "decisions:test"
        response {:schema "ZIL-EXCHANGE/1"
                  :request_id "request:decision"
                  :protocol_version 1
                  :operation "authorize"
                  :status "ok"
                  :authority "lean"
                  :assurance "validated"
                  :input_sha256 (decision "input")
                  :result_sha256 (decision "payload")
                  :errors []
                  :warnings []}]
    (with-redefs [command/execute! (fn [& _] response)]
      (let [result (durable/invoke-and-record!
                    :control-plane database
                    {:stream stream
                     :expected-revision 0
                     :actor "agent:a"
                     :command "authorize"
                     :input-path "model.zc"
                     :arguments ["doc:x" "viewer" "user:y"]
                     :workflow-id "workflow:authorization"})]
        (is (:ok result))
        (is (= "semantic-decision"
               (get-in result [:event :event :event_type])))
        (is (= 1 (:revision (:event result))))
        (is (:ok (store/verify-store database stream)))))
    (with-redefs [command/execute!
                  (fn [& _]
                    (throw (ex-info "worker unavailable" {:kind :transport-error})))]
      (is (thrown? Exception
                   (durable/invoke-and-record!
                    :control-plane database
                    {:stream stream
                     :expected-revision 1
                     :actor "agent:a"
                     :command "authorize"
                     :input-path "model.zc"
                     :arguments []})))
      (is (= 1 (count (store/read-events database stream)))))))

(deftest workflow-projection-snapshot-is-idempotent-and-immutable
  (let [database (temp-db)
        stream "workflow:projection"
        values
        [{:stream stream :event-type "action-consumed" :actor "agent:a"
          :request-id "request:consume" :decision-sha256 (decision "consumed")
          :payload {:workflow_id "workflow:1" :action_id "action:1"
                    :lean_status "consumed"}}
         {:stream stream :event-type "recovery-completed" :actor "agent:b"
          :request-id "request:recovery" :decision-sha256 (decision "recovered")
          :payload {:workflow_id "workflow:1" :action_id "action:1"
                    :lean_status "recovered" :safe true}}]]
    (store/append-events! database stream 0 values)
    (let [first-result (durable/project-workflows! database stream)
          second-result (durable/project-workflows! database stream)
          summary (durable/workflow-status database stream)]
      (is (:ok first-result))
      (is (false? (get-in first-result [:snapshot :existing])))
      (is (true? (get-in second-result [:snapshot :existing])))
      (is (= 2 (get-in summary [:projection :event-count])))
      (is (= "recovery-completed"
             (get-in summary [:projection :workflows 0 :last-event-type])))
      (is (:ok (:integrity summary)))
      (is (thrown-with-msg?
           clojure.lang.ExceptionInfo
           #"snapshot is immutable"
           (store/write-snapshot! database stream 2
                                  "zil.control.workflow/v1"
                                  {:different true}))))))
