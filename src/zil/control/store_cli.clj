(ns zil.control.store-cli
  "CLI for durable control-plane decisions and workflow observations."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.edn :as edn]
            [clojure.string :as str]
            [zil.control.durable :as durable]
            [zil.control.runtime :as runtime]
            [zil.store.control-event :as store]))

(def usage
  (str "zil-control-store status <database> <stream>\n"
       "zil-control-store verify <database> <stream>\n"
       "zil-control-store project <database> <stream>\n"
       "zil-control-store invoke <database> <stream> <expected-revision> <actor> "
       "<operation> <input-path> [arguments...]\n"
       "zil-control-store record <database> <stream> <expected-revision> <actor> "
       "<event-type> <decision-sha256> <payload.edn>"))

(defn- revision! [value]
  (or (parse-long value)
      (throw (ex-info "expected revision must be an integer"
                      {:kind :invalid-command :value value}))))

(defn- print-json [value]
  (println (json/write-str value)))

(defn- invoke! [database stream expected actor operation input-path arguments]
  (let [control-plane (runtime/start! {:pool-size 1})]
    (try
      (durable/invoke-and-record!
       control-plane database
       {:stream stream
        :expected-revision expected
        :actor actor
        :command operation
        :input-path input-path
        :arguments arguments})
      (finally
        (runtime/stop! control-plane)))))

(defn- record! [database stream expected actor event-type decision-sha payload-path]
  (let [payload (edn/read-string (slurp payload-path))]
    (durable/record-workflow-event!
     database
     {:stream stream
      :expected-revision expected
      :actor actor
      :event-type event-type
      :request-id (or (:request_id payload) (:request-id payload))
      :base-revision (or (:base_revision payload) (:base-revision payload) "-")
      :context-bundle-id (or (:context_bundle_id payload)
                             (:context-bundle-id payload) "-")
      :decision-sha256 decision-sha
      :plugin-id (or (:plugin_id payload) (:plugin-id payload) "-")
      :payload payload})))

(defn- command-result [command database stream tail]
  (case command
    "status"
    (do
      (when (seq tail) (throw (ex-info usage {:kind :invalid-command})))
      (let [value (durable/workflow-status database stream)]
        {:value value :ok (get-in value [:integrity :ok])}))

    "verify"
    (do
      (when (seq tail) (throw (ex-info usage {:kind :invalid-command})))
      (let [value (store/verify-store database stream)]
        {:value value :ok (:ok value)}))

    "project"
    (do
      (when (seq tail) (throw (ex-info usage {:kind :invalid-command})))
      (let [value (durable/project-workflows! database stream)]
        {:value value :ok (:ok value)}))

    "invoke"
    (let [[expected actor operation input-path & arguments] tail]
      (when (some str/blank? [expected actor operation input-path])
        (throw (ex-info usage {:kind :invalid-command})))
      (let [value (invoke! database stream (revision! expected)
                           actor operation input-path arguments)]
        {:value value :ok (:ok value)}))

    "record"
    (let [[expected actor event-type decision-sha payload-path & extra] tail]
      (when (or (some str/blank?
                      [expected actor event-type decision-sha payload-path])
                (seq extra))
        (throw (ex-info usage {:kind :invalid-command})))
      (let [value (record! database stream (revision! expected)
                           actor event-type decision-sha payload-path)]
        {:value value :ok (:ok value)}))

    (throw (ex-info usage {:kind :invalid-command :command command}))))

(defn -main [& args]
  (try
    (let [[command database stream & tail] args]
      (when (or (str/blank? command) (str/blank? database) (str/blank? stream))
        (throw (ex-info usage {:kind :invalid-command})))
      (let [{:keys [value ok]} (command-result command database stream tail)]
        (print-json value)
        (System/exit (if ok 0 1))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
