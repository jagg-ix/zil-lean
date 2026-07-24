(ns zil.control.event
  "Canonical control-plane events and durable transaction receipts."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.worker.client :as worker-client]))

(def event-schema "ZIL-CONTROL-EVENT/1")
(def receipt-schema "ZIL-CONTROL-RECEIPT/1")
(def empty-chain-sha256 (worker-client/sha256-text ""))

(def ^:private event-fields
  [:schema :event_id :stream :event_type :actor :request_id :base_revision
   :context_bundle_id :decision_sha256 :plugin_id :payload_sha256 :payload])

(def ^:private receipt-fields
  [:schema :receipt_id :stream :base_revision :final_revision :event_count
   :batch_sha256 :committed_at_epoch_ms])

(defn- canonicalize [value]
  (cond
    (map? value)
    (into (sorted-map-by #(compare (str %1) (str %2)))
          (map (fn [[key item]] [(name key) (canonicalize item)]))
          value)

    (set? value) (mapv canonicalize (sort-by str value))
    (sequential? value) (mapv canonicalize value)
    (keyword? value) (name value)
    (symbol? value) (str value)
    :else value))

(defn canonical-json [fields value]
  (json/write-str
   (into (array-map)
         (map (fn [field] [(name field) (get value field)]))
         fields)))

(defn valid-sha256? [value]
  (boolean (re-matches #"sha256:[0-9a-f]{64}" (str value))))

(defn- optional-binding [value]
  (let [value (str (or value "-"))]
    (if (str/blank? value) "-" value)))

(defn prepare-event
  "Normalize one event and derive its stable identity from exact canonical bytes.

  `decision-sha256` binds the event to a Lean response or other authoritative
  decision. Operational-only events use the SHA-256 of their exact evidence
  payload rather than an invented semantic decision."
  [{:keys [event-id stream event-type actor request-id base-revision
           context-bundle-id decision-sha256 plugin-id payload]}]
  (let [payload (canonicalize (or payload {}))
        payload-sha256 (worker-client/sha256-text (json/write-str payload))
        value (array-map
               :schema event-schema
               :event_id ""
               :stream (str stream)
               :event_type (str event-type)
               :actor (str actor)
               :request_id (optional-binding request-id)
               :base_revision (optional-binding base-revision)
               :context_bundle_id (optional-binding context-bundle-id)
               :decision_sha256 (str decision-sha256)
               :plugin_id (optional-binding plugin-id)
               :payload_sha256 payload-sha256
               :payload payload)
        derived-id (str "event:"
                        (subs (worker-client/sha256-text
                               (canonical-json event-fields value)) 7))
        value (assoc value :event_id (or event-id derived-id))]
    (when (str/blank? (:stream value))
      (throw (ex-info "control event stream must be nonempty" {:kind :event-error})))
    (when (str/blank? (:event_type value))
      (throw (ex-info "control event type must be nonempty" {:kind :event-error})))
    (when (str/blank? (:actor value))
      (throw (ex-info "control event actor must be nonempty" {:kind :event-error})))
    (when-not (valid-sha256? (:decision_sha256 value))
      (throw (ex-info "control event decision_sha256 is invalid"
                      {:kind :event-error :decision_sha256 (:decision_sha256 value)})))
    value))

(defn event-json [event]
  (canonical-json event-fields (prepare-event event)))

(defn event-sha256 [event previous-event-sha256 revision]
  (when-not (valid-sha256? previous-event-sha256)
    (throw (ex-info "previous event digest is invalid"
                    {:kind :event-error :previous-event-sha256 previous-event-sha256})))
  (worker-client/sha256-text
   (str previous-event-sha256 "\n" revision "\n" (event-json event))))

(defn prepare-receipt
  [{:keys [receipt-id stream base-revision final-revision event-count
           batch-sha256 committed-at-epoch-ms]}]
  (let [value (array-map
               :schema receipt-schema
               :receipt_id ""
               :stream (str stream)
               :base_revision (long base-revision)
               :final_revision (long final-revision)
               :event_count (long event-count)
               :batch_sha256 (str batch-sha256)
               :committed_at_epoch_ms (long committed-at-epoch-ms))
        derived-id (str "receipt:"
                        (subs (worker-client/sha256-text
                               (canonical-json receipt-fields value)) 7))]
    (when-not (valid-sha256? (:batch_sha256 value))
      (throw (ex-info "control receipt batch_sha256 is invalid"
                      {:kind :receipt-error :batch-sha256 (:batch_sha256 value)})))
    (assoc value :receipt_id (or receipt-id derived-id))))

(defn receipt-json [receipt]
  (canonical-json receipt-fields (prepare-receipt receipt)))

(defn receipt-sha256 [receipt]
  (worker-client/sha256-text (receipt-json receipt)))
