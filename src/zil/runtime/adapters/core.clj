(ns zil.runtime.adapters.core
  "Adapter registry and dispatch for ingestion sources."
  (:require [clojure.string :as str]))

(defonce ^:private adapter-registry
  (atom {}))

(defn normalize-type
  [t]
  (cond
    (keyword? t) (keyword (str/lower-case (name t)))
    (string? t) (keyword (str/lower-case (str/trim t)))
    :else (throw (ex-info "Adapter type must be keyword|string" {:type t}))))

(defn register-adapter!
  [t adapter-fn]
  (let [k (normalize-type t)]
    (swap! adapter-registry assoc k adapter-fn)
    k))

(defn adapter-for
  [t]
  (get @adapter-registry (normalize-type t)))

(defn supported-types
  []
  (->> @adapter-registry keys sort vec))

(defn read-records
  "Execute one adapter in pull mode and return records."
  [datasource opts]
  (let [t (or (:type datasource)
              (get-in datasource [:attrs :type]))
        adapter (adapter-for t)]
    (when-not adapter
      (throw (ex-info "No adapter registered for datasource type"
                      {:type t
                       :supported (supported-types)})))
    (adapter datasource opts)))
