(ns zil.store.control-event
  "Hash-chained control-plane event streams over the existing SQLite connection layer."
  (:require [clojure.data.json :as json]
            [zil.control.event :as event]
            [zil.store.sqlite :as sqlite]
            [zil.worker.client :as worker-client]))

(def schema
  ["CREATE TABLE IF NOT EXISTS control_stream_heads (stream TEXT PRIMARY KEY, current_revision INTEGER NOT NULL, current_event_sha256 TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS control_batches (receipt_id TEXT PRIMARY KEY, stream TEXT NOT NULL, base_revision INTEGER NOT NULL, final_revision INTEGER NOT NULL, event_count INTEGER NOT NULL, batch_sha256 TEXT NOT NULL, committed_at_epoch_ms INTEGER NOT NULL, receipt_sha256 TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS control_events (stream TEXT NOT NULL, revision INTEGER NOT NULL, event_id TEXT UNIQUE NOT NULL, event_type TEXT NOT NULL, actor TEXT NOT NULL, request_id TEXT NOT NULL, base_revision TEXT NOT NULL, context_bundle_id TEXT NOT NULL, decision_sha256 TEXT NOT NULL, plugin_id TEXT NOT NULL, payload_json TEXT NOT NULL, payload_sha256 TEXT NOT NULL, previous_event_sha256 TEXT NOT NULL, event_sha256 TEXT NOT NULL, receipt_id TEXT NOT NULL REFERENCES control_batches(receipt_id), PRIMARY KEY(stream, revision))"
   "CREATE TABLE IF NOT EXISTS control_snapshots (stream TEXT NOT NULL, revision INTEGER NOT NULL, reducer_id TEXT NOT NULL, state_json TEXT NOT NULL, state_sha256 TEXT NOT NULL, event_sha256 TEXT NOT NULL, PRIMARY KEY(stream, revision, reducer_id))"])

(defn initialize! [conn]
  (sqlite/initialize! conn)
  (with-open [statement (.createStatement conn)]
    (doseq [sql schema] (.execute statement sql)))
  conn)

(defn connect [path]
  (initialize! (sqlite/connect path)))

(defn- execute! [conn sql parameters]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (.executeUpdate statement)))

(defn- query-row [conn sql parameters columns]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (with-open [rows (.executeQuery statement)]
      (when (.next rows)
        (into {}
              (map-indexed (fn [index column]
                             [column (.getObject rows (inc index))])
                           columns))))))

(defn current-head [conn stream]
  (or (query-row conn
                 "SELECT current_revision,current_event_sha256 FROM control_stream_heads WHERE stream=?"
                 [stream] [:revision :event-sha256])
      {:revision 0 :event-sha256 event/empty-chain-sha256}))

(defn current-revision [conn stream]
  (long (:revision (current-head conn stream))))

(defn- stored-event [revision previous-sha event-value]
  (let [prepared (event/prepare-event event-value)
        event-sha (event/event-sha256 prepared previous-sha revision)]
    {:revision revision
     :previous-event-sha256 previous-sha
     :event-sha256 event-sha
     :event prepared}))

(defn append-events!
  "Append a nonempty event batch under an expected-revision compare-and-swap.

  The returned receipt binds the exact event sequence and final revision. No event
  is committed when the stream head changed or any event is invalid."
  [db-path stream expected-revision events]
  (when-not (seq events)
    (throw (ex-info "control event batch must be nonempty" {:kind :event-store-error})))
  (with-open [conn (connect db-path)]
    (.setAutoCommit conn false)
    (try
      (let [{current :revision previous :event-sha256} (current-head conn stream)]
        (when-not (= (long current) (long expected-revision))
          (throw (ex-info "control event expected revision conflict"
                          {:kind :revision-conflict
                           :stream stream
                           :expected expected-revision
                           :current current})))
        (let [stored
              (loop [remaining (seq events)
                     revision (inc (long current))
                     previous-sha previous
                     out []]
                (if-not remaining
                  out
                  (let [value (stored-event revision previous-sha (first remaining))]
                    (when-not (= stream (get-in value [:event :stream]))
                      (throw (ex-info "control event stream disagrees with append target"
                                      {:kind :event-store-error
                                       :target stream
                                       :event-stream (get-in value [:event :stream])})))
                    (recur (next remaining) (inc revision)
                           (:event-sha256 value) (conj out value)))))
              batch-sha (worker-client/sha256-text
                         (json/write-str
                          (mapv (fn [{:keys [revision event-sha256]}]
                                  {:revision revision :event_sha256 event-sha256})
                                stored)))
              committed-at (System/currentTimeMillis)
              receipt (event/prepare-receipt
                       {:stream stream
                        :base-revision current
                        :final-revision (:revision (last stored))
                        :event-count (count stored)
                        :batch-sha256 batch-sha
                        :committed-at-epoch-ms committed-at})
              receipt-sha (event/receipt-sha256 receipt)]
          (execute! conn
                    "INSERT INTO control_batches(receipt_id,stream,base_revision,final_revision,event_count,batch_sha256,committed_at_epoch_ms,receipt_sha256) VALUES(?,?,?,?,?,?,?,?)"
                    [(:receipt_id receipt) stream current (:final_revision receipt)
                     (:event_count receipt) batch-sha committed-at receipt-sha])
          (doseq [{:keys [revision previous-event-sha256 event-sha256 event]} stored]
            (execute! conn
                      "INSERT INTO control_events(stream,revision,event_id,event_type,actor,request_id,base_revision,context_bundle_id,decision_sha256,plugin_id,payload_json,payload_sha256,previous_event_sha256,event_sha256,receipt_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
                      [stream revision (:event_id event) (:event_type event) (:actor event)
                       (:request_id event) (:base_revision event) (:context_bundle_id event)
                       (:decision_sha256 event) (:plugin_id event)
                       (json/write-str (:payload event)) (:payload_sha256 event)
                       previous-event-sha256 event-sha256 (:receipt_id receipt)]))
          (let [final-event-sha (:event-sha256 (last stored))]
            (execute! conn
                      "INSERT INTO control_stream_heads(stream,current_revision,current_event_sha256) VALUES(?,?,?) ON CONFLICT(stream) DO UPDATE SET current_revision=excluded.current_revision,current_event_sha256=excluded.current_event_sha256"
                      [stream (:final_revision receipt) final-event-sha]))
          (.commit conn)
          {:ok true
           :receipt receipt
           :receipt_sha256 receipt-sha
           :events stored}))
      (catch Exception error
        (.rollback conn)
        (throw error)))))

(defn read-events
  ([db-path stream] (read-events db-path stream 1 Long/MAX_VALUE))
  ([db-path stream from-revision to-revision]
   (with-open [conn (connect db-path)
               statement (.prepareStatement conn
                 "SELECT revision,event_id,event_type,actor,request_id,base_revision,context_bundle_id,decision_sha256,plugin_id,payload_json,payload_sha256,previous_event_sha256,event_sha256,receipt_id FROM control_events WHERE stream=? AND revision>=? AND revision<=? ORDER BY revision")]
     (.setString statement 1 stream)
     (.setLong statement 2 (long from-revision))
     (.setLong statement 3 (long to-revision))
     (with-open [rows (.executeQuery statement)]
       (loop [out []]
         (if (.next rows)
           (recur
            (conj out
                  {:revision (.getLong rows 1)
                   :event {:schema event/event-schema
                           :event_id (.getString rows 2)
                           :stream stream
                           :event_type (.getString rows 3)
                           :actor (.getString rows 4)
                           :request_id (.getString rows 5)
                           :base_revision (.getString rows 6)
                           :context_bundle_id (.getString rows 7)
                           :decision_sha256 (.getString rows 8)
                           :plugin_id (.getString rows 9)
                           :payload (json/read-str (.getString rows 10))
                           :payload_sha256 (.getString rows 11)}
                   :previous-event-sha256 (.getString rows 12)
                   :event-sha256 (.getString rows 13)
                   :receipt-id (.getString rows 14)}))
           out))))))

(defn verify-stream [db-path stream]
  (let [events (read-events db-path stream)]
    (loop [remaining events
           expected-revision 1
           previous-sha event/empty-chain-sha256]
      (if-not (seq remaining)
        (with-open [conn (connect db-path)]
          (let [head (current-head conn stream)]
            {:ok (and (= (dec expected-revision) (long (:revision head)))
                      (= previous-sha (:event-sha256 head)))
             :stream stream
             :revision (:revision head)
             :event-count (count events)
             :event-sha256 (:event-sha256 head)}))
        (let [{:keys [revision event previous-event-sha256 event-sha256]} (first remaining)
              computed (event/event-sha256 event previous-sha revision)]
          (if (and (= expected-revision revision)
                   (= previous-sha previous-event-sha256)
                   (= computed event-sha256))
            (recur (next remaining) (inc expected-revision) event-sha256)
            {:ok false
             :stream stream
             :revision revision
             :expected-revision expected-revision
             :expected-previous-sha256 previous-sha
             :stored-previous-sha256 previous-event-sha256
             :computed-event-sha256 computed
             :stored-event-sha256 event-sha256}))))))

(defn write-snapshot!
  [db-path stream revision reducer-id state]
  (with-open [conn (connect db-path)]
    (let [head (current-head conn stream)]
      (when (> (long revision) (long (:revision head)))
        (throw (ex-info "snapshot revision exceeds stream head"
                        {:kind :snapshot-error :stream stream
                         :revision revision :head (:revision head)})))
      (let [event-row (query-row conn
                                 "SELECT event_sha256 FROM control_events WHERE stream=? AND revision=?"
                                 [stream revision] [:event-sha256])
            state-json (json/write-str state)
            state-sha (worker-client/sha256-text state-json)]
        (when-not event-row
          (throw (ex-info "snapshot revision has no event"
                          {:kind :snapshot-error :stream stream :revision revision})))
        (execute! conn
                  "INSERT INTO control_snapshots(stream,revision,reducer_id,state_json,state_sha256,event_sha256) VALUES(?,?,?,?,?,?)"
                  [stream revision reducer-id state-json state-sha (:event-sha256 event-row)])
        {:ok true :stream stream :revision revision :reducer-id reducer-id
         :state-sha256 state-sha :event-sha256 (:event-sha256 event-row)}))))

(defn read-snapshot [db-path stream revision reducer-id]
  (with-open [conn (connect db-path)]
    (when-let [row (query-row conn
                             "SELECT state_json,state_sha256,event_sha256 FROM control_snapshots WHERE stream=? AND revision=? AND reducer_id=?"
                             [stream revision reducer-id]
                             [:state-json :state-sha256 :event-sha256])]
      {:stream stream :revision revision :reducer-id reducer-id
       :state (json/read-str (:state-json row) :key-fn keyword)
       :state-sha256 (:state-sha256 row)
       :event-sha256 (:event-sha256 row)})))
