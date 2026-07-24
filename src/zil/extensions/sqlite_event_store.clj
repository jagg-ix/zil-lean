(ns zil.extensions.sqlite-event-store
  "Reference StoreBackend for hash-chained control events and snapshots."
  (:require [zil.plugin.api :as api]
            [zil.store.control-event :as store]))

(def capabilities ["control-event-store" "snapshot-store"])

(defrecord SQLiteEventStore [extension-manifest config]
  api/Extension
  (extension-manifest [_] extension-manifest)
  (start-extension! [this _] this)
  (stop-extension! [_ _] nil)

  api/Capability
  (provided-capabilities [_] capabilities)

  api/StoreBackend
  (open-store! [_ _ options]
    (let [path (or (:path options) (:path config))
          stream (or (:stream options) (:stream config))]
      (when-not path
        (throw (ex-info "SQLite event store requires :path"
                        {:kind :extension-configuration-error})))
      (with-open [conn (store/connect path)]
        {:path path
         :stream stream
         :initialized true})))
  (close-store! [_ _ _] nil)
  (append-events! [_ _ handle expected-revision events]
    (let [stream (or (:stream handle)
                     (:stream (first events))
                     (:stream config))]
      (when-not stream
        (throw (ex-info "SQLite event store append requires a stream"
                        {:kind :extension-input-error})))
      (store/append-events! (:path handle) stream expected-revision events)))
  (read-events [_ _ handle from-revision to-revision]
    (let [stream (or (:stream handle) (:stream config))]
      (when-not stream
        (throw (ex-info "SQLite event store read requires a stream"
                        {:kind :extension-input-error})))
      (store/read-events (:path handle) stream from-revision to-revision)))

  api/CommandProvider
  (provided-commands [_]
    {"event-store-status"
     {:summary "Read and verify one control event stream"
      :arguments ["database" "stream"]
      :authority :clojure}
     "event-store-project"
     {:summary "Materialize the operational workflow projection"
      :arguments ["database" "stream"]
      :authority :clojure}})
  (invoke-extension-command! [_ command _ arguments]
    (when-not (= 2 (count arguments))
      (throw (ex-info "event store commands require database and stream"
                      {:kind :extension-input-error :arguments arguments})))
    (let [[database stream] arguments]
      (case command
        "event-store-status"
        {:stream stream
         :revision (with-open [conn (store/connect database)]
                     (store/current-revision conn stream))
         :integrity (store/verify-store database stream)}

        "event-store-project"
        (let [durable (requiring-resolve 'zil.control.durable/workflow-status)]
          (durable database stream))

        (throw (ex-info "unsupported SQLite event store command"
                        {:kind :unknown-extension-command :command command}))))))

(defn create [extension-manifest config]
  (->SQLiteEventStore extension-manifest config))
