(ns zil.control.durable
  "Durable wrappers around Lean-authoritative control-plane operations."
  (:require [clojure.data.json :as json]
            [zil.control.command :as command]
            [zil.control.event :as event]
            [zil.control.workflow :as workflow]
            [zil.store.control-event :as store]
            [zil.worker.client :as worker-client]))

(defn- semantic-payload [response]
  (array-map
   :schema (:schema response)
   :request_id (:request_id response)
   :protocol_version (:protocol_version response)
   :operation (:operation response)
   :status (:status response)
   :authority (:authority response)
   :assurance (:assurance response)
   :input_sha256 (:input_sha256 response)
   :result_sha256 (:result_sha256 response)
   :errors (vec (:errors response))
   :warnings (vec (:warnings response))))

(defn invoke-and-record!
  "Invoke one Lean-authoritative command and append its exact decision envelope."
  [control-plane db-path
   {:keys [stream expected-revision actor command input-path arguments base-revision
           context-bundle-id plugin-id workflow-id request-id timeout-ms]
    :or {arguments [] base-revision "-" plugin-id "-"}}]
  (let [response (command/execute!
                  control-plane command input-path arguments
                  (cond-> {:base-revision base-revision}
                    request-id (assoc :request-id request-id)
                    timeout-ms (assoc :timeout-ms timeout-ms)))
        decision-sha (or (:result_sha256 response)
                         (worker-client/sha256-text
                          (json/write-str (semantic-payload response))))
        value (event/prepare-event
               {:stream stream
                :event-type "semantic-decision"
                :actor actor
                :request-id (:request_id response)
                :base-revision base-revision
                :context-bundle-id context-bundle-id
                :decision-sha256 decision-sha
                :plugin-id plugin-id
                :payload {:workflow_id (or workflow-id (:request_id response))
                          :response (semantic-payload response)}})
        persisted (store/append-events! db-path stream expected-revision [value])]
    {:ok (= "ok" (:status response))
     :response response
     :event (first (:events persisted))
     :receipt (:receipt persisted)
     :receipt-sha256 (:receipt_sha256 persisted)}))

(defn record-workflow-event!
  "Append an observation already bound to an authoritative decision or evidence hash."
  [db-path
   {:keys [stream expected-revision event-type actor request-id base-revision
           context-bundle-id decision-sha256 plugin-id payload]}]
  (workflow/validate-workflow-event!
   {:event-type event-type :request-id request-id :payload payload})
  (store/append-events!
   db-path stream expected-revision
   [(event/prepare-event
     {:stream stream
      :event-type event-type
      :actor actor
      :request-id request-id
      :base-revision base-revision
      :context-bundle-id context-bundle-id
      :decision-sha256 decision-sha256
      :plugin-id plugin-id
      :payload payload})]))

(defn project-workflows!
  "Replay a stream into an immutable nonauthoritative workflow snapshot."
  [db-path stream]
  (let [events (store/read-events db-path stream)
        projection (workflow/reduce-events events)
        revision (:revision projection)]
    (if (zero? revision)
      {:ok true :stream stream :revision 0 :projection projection :snapshot nil}
      {:ok true
       :stream stream
       :revision revision
       :projection projection
       :snapshot (store/write-snapshot! db-path stream revision workflow/reducer-id projection)})))

(defn workflow-status [db-path stream]
  (let [events (store/read-events db-path stream)
        projection (workflow/reduce-events events)]
    {:stream stream
     :integrity (store/verify-store db-path stream)
     :projection (workflow/workflow-summary projection)}))
