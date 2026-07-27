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

(declare canonical-value)

(defn- canonical-key [key]
  (cond
    (string? key) key
    (keyword? key) (name key)
    (symbol? key) (str key)
    :else
    (throw (ex-info "canonical map keys must be strings, keywords, or symbols"
                    {:kind :canonicalization-error :key key}))))

(defn- canonical-map [value]
  (reduce
   (fn [out [key item]]
     (let [normalized-key (canonical-key key)]
       (when (contains? out normalized-key)
         (throw (ex-info "canonical map keys collide after normalization"
                         {:kind :canonicalization-error
                          :key normalized-key})))
       (assoc out normalized-key (canonical-value item))))
   (sorted-map)
   value))

(defn- canonical-set [value]
  (let [items (mapv canonical-value (sort-by str value))]
    (when-not (= (count items) (count (distinct items)))
      (throw (ex-info "canonical set values collide after normalization"
                      {:kind :canonicalization-error})))
    items))

(defn canonical-value [value]
  (cond
    (map? value) (canonical-map value)
    (set? value) (canonical-set value)
    (sequential? value) (mapv canonical-value value)
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

(defn- field [value kebab snake]
  (if (contains? value kebab) (get value kebab) (get value snake)))

(defn- optional-binding [value]
  (let [value (str (or value "-"))]
    (if (str/blank? value) "-" value)))

(defn prepare-event
  "Normalize one event and derive its stable identity from exact canonical bytes."
  [input]
  (let [event-id (field input :event-id :event_id)
        stream (field input :stream :stream)
        event-type (field input :event-type :event_type)
        actor (field input :actor :actor)
        request-id (field input :request-id :request_id)
        base-revision (field input :base-revision :base_revision)
        context-bundle-id (field input :context-bundle-id :context_bundle_id)
        decision-sha256 (field input :decision-sha256 :decision_sha256)
        plugin-id (field input :plugin-id :plugin_id)
        payload (canonical-value (or (:payload input) {}))
        payload-sha256 (worker-client/sha256-text (json/write-str payload))
        value (array-map
               :schema event-schema
               :event_id ""
               :stream (str (or stream ""))
               :event_type (str (or event-type ""))
               :actor (str (or actor ""))
               :request_id (optional-binding request-id)
               :base_revision (optional-binding base-revision)
               :context_bundle_id (optional-binding context-bundle-id)
               :decision_sha256 (str (or decision-sha256 ""))
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

(defn prepare-receipt [input]
  (let [receipt-id (field input :receipt-id :receipt_id)
        stream (field input :stream :stream)
        base-revision (field input :base-revision :base_revision)
        final-revision (field input :final-revision :final_revision)
        event-count (field input :event-count :event_count)
        batch-sha256 (field input :batch-sha256 :batch_sha256)
        committed-at (field input :committed-at-epoch-ms :committed_at_epoch_ms)
        value (array-map
               :schema receipt-schema
               :receipt_id ""
               :stream (str (or stream ""))
               :base_revision (long base-revision)
               :final_revision (long final-revision)
               :event_count (long event-count)
               :batch_sha256 (str batch-sha256)
               :committed_at_epoch_ms (long committed-at))
        derived-id (str "receipt:"
                        (subs (worker-client/sha256-text
                               (canonical-json receipt-fields value)) 7))]
    (when (str/blank? (:stream value))
      (throw (ex-info "control receipt stream must be nonempty" {:kind :receipt-error})))
    (when-not (valid-sha256? (:batch_sha256 value))
      (throw (ex-info "control receipt batch_sha256 is invalid"
                      {:kind :receipt-error :batch-sha256 (:batch_sha256 value)})))
    (assoc value :receipt_id (or receipt-id derived-id))))

(defn receipt-json [receipt]
  (canonical-json receipt-fields (prepare-receipt receipt)))

(defn receipt-sha256 [receipt]
  (worker-client/sha256-text (receipt-json receipt)))
