(ns zil.runtime.ingest
  "Ingest pipeline for datasource declarations.

  Phase 3 scope:
  - adapter registry dispatch
  - pull-mode read of datasource records
  - lowering records into canonical tuple facts
  - DataScript transact integration"
  (:require [clojure.string :as str]
            [zil.lower :as zl]
            [zil.runtime.adapters.command]
            [zil.runtime.adapters.core :as ac]
            [zil.runtime.adapters.cucumber]
            [zil.runtime.adapters.file]
            [zil.runtime.adapters.rest]
            [zil.runtime.datascript :as zr]))

(defn datasource-declarations
  [compiled]
  (->> (:declarations compiled)
       (filter #(= :datasource (:kind %)))
       vec))

(defn declaration->datasource-spec
  [{:keys [name] :as decl}]
  (let [decl* (zl/normalized-declaration decl)]
    {:id (zl/entity-id :datasource name)
     :name name
     :kind :datasource
     :type (get-in decl* [:attrs :type])
     :attrs (:attrs decl*)}))

(defn- metric-id
  [v]
  (let [s (cond
            (string? v) v
            (keyword? v) (name v)
            :else (str v))]
    (if (str/includes? s ":")
      s
      (str "metric:" s))))

(defn- relation-key
  [k]
  (cond
    (keyword? k) k
    (string? k) (keyword (str/replace (str/lower-case k) #"[^a-z0-9_:\-\.]" "_"))
    :else (keyword (str k))))

(defn- normalize-event-id
  [v]
  (let [s (cond
            (keyword? v) (name v)
            (string? v) (str/trim v)
            :else (some-> v str str/trim))]
    (when (and s (not (str/blank? s)))
      (if (str/includes? s ":")
        s
        (str "event:" s)))))

(defn- event-keyword
  [v]
  (when-let [eid (normalize-event-id v)]
    (-> eid
        (str/replace #"[^A-Za-z0-9_:\-\.]" "_")
        keyword)))

(defn- event-id-from-record
  [record]
  (or (normalize-event-id (:event_id record))
      (normalize-event-id (:event-id record))
      (normalize-event-id (:event record))))

(defn- envelope-fact
  [datasource-id record ingest-ts]
  {:object datasource-id
   :relation :ingested_record
   :subject "value:record"
   :attrs {:ingest_ts ingest-ts
           :payload record}})

(defn- metric-observation-facts
  [datasource-id record ingest-ts]
  (let [metric (:metric record)
        value (:value record)
        metrics (:metrics record)]
    (cond
      (and metric (contains? record :value))
      [{:object (metric-id metric)
        :relation :observed_from
        :subject datasource-id
        :attrs {:value value
                :ingest_ts ingest-ts}}]

      (map? metrics)
      (for [[mk mv] metrics]
        {:object (metric-id mk)
         :relation :observed_from
         :subject datasource-id
         :attrs {:value mv
                 :ingest_ts ingest-ts}})

      :else [])))

(defn- scalar-field-facts
  [datasource-id record ingest-ts]
  (for [[k v] record
        :when (and (not= k :metric)
                   (not= k :value)
                   (not= k :metrics)
                   (not= k :before)
                   (not= k :vector_clock)
                   (not= k :event_id)
                   (not= k :event-id))]
    {:object datasource-id
     :relation (relation-key k)
     :subject (zl/subject-value v)
     :attrs {:ingest_ts ingest-ts}}))

(defn- vector-clock-facts
  [record ingest-ts]
  (let [eid (event-id-from-record record)
        vc (:vector_clock record)
        vc* (when (map? vc) (zr/normalize-vector-clock vc))]
    (if (and eid (map? vc*))
      (for [[actor counter] vc*]
        {:object eid
         :relation :vc_component
         :subject (str "actor:" (if (keyword? actor) (name actor) actor))
         :attrs {:counter counter
                 :ingest_ts ingest-ts}})
      [])))

(defn record->facts
  [datasource-id record ingest-ts]
  (let [record* (if (map? record) record {:value record})
        event-k (event-keyword (event-id-from-record record*))]
    (vec
     (map
      #(cond-> %
         event-k (assoc :event event-k))
      (concat
       [(envelope-fact datasource-id record* ingest-ts)]
       (metric-observation-facts datasource-id record* ingest-ts)
       (vector-clock-facts record* ingest-ts)
       (when (map? record*)
         (scalar-field-facts datasource-id record* ingest-ts)))))))

(defn- explicit-before-edges
  [record]
  (let [right (event-keyword (event-id-from-record record))
        lefts (or (:before record) [])]
    (if right
      (->> lefts
           (map event-keyword)
           (remove nil?)
           (mapv (fn [left] {:left left :right right})))
      [])))

(defn- vector-clock-event
  [record]
  (let [event-k (event-keyword (event-id-from-record record))
        vc (:vector_clock record)
        vc* (when (map? vc) (zr/normalize-vector-clock vc))]
    (when (and event-k (map? vc*))
      {:event event-k
       :vector_clock vc*})))

(defn ingest-datasource-once!
  "Run one datasource adapter once and transact resulting facts."
  ([conn datasource-spec] (ingest-datasource-once! conn datasource-spec {}))
  ([conn datasource-spec {:keys [revision event]
                          :or {revision nil}}]
   (let [ingest-ts (System/currentTimeMillis)
         records (ac/read-records datasource-spec {})
         facts (mapcat #(record->facts (:id datasource-spec) % ingest-ts) records)
         explicit-edges (mapcat explicit-before-edges records)
         vc-events (keep vector-clock-event records)
         derived-edges (zr/derive-before-edges-from-vector-clocks vc-events)
         before-edges (vec (distinct (concat explicit-edges derived-edges)))
         revision* (or revision ingest-ts)
         event* (or event
                    (keyword
                     (str "ingest_"
                          (str/replace (:id datasource-spec) #":" "_"))))
         tx-facts (mapv #(assoc % :revision revision* :event (or (:event %) event*)) facts)]
     (zr/transact-facts! conn tx-facts)
     (when (seq before-edges)
       (zr/transact-before-edges! conn before-edges))
     {:datasource (:id datasource-spec)
      :type (:type datasource-spec)
      :records (count records)
      :facts (count tx-facts)
      :before_edges (count before-edges)
      :before_edges_explicit (count explicit-edges)
      :before_edges_derived (count derived-edges)})))

(defn ingest-all!
  "Run all DATASOURCE declarations from a compiled program."
  ([conn compiled] (ingest-all! conn compiled {}))
  ([conn compiled opts]
   (let [sources (mapv declaration->datasource-spec (datasource-declarations compiled))
         by-source (mapv #(ingest-datasource-once! conn % opts) sources)]
     {:sources (count sources)
      :records (reduce + 0 (map :records by-source))
      :facts (reduce + 0 (map :facts by-source))
      :by_source by-source})))

(defn poll-mode
  [datasource-spec]
  (ac/normalize-type
   (or (get-in datasource-spec [:attrs :poll_mode])
       :event)))

(defn poll-interval-ms
  [datasource-spec]
  (long
   (or (get-in datasource-spec [:attrs :poll_every_ms])
       (get-in datasource-spec [:attrs :interval_ms])
       5000)))

(defn- next-revision
  [state]
  (swap! state inc))

(defn start-poller!
  "Start ingest for one datasource.

  For `poll_mode=event`, runs once and returns a completed handle.
  For `poll_mode=interval`, starts a background future."
  ([conn datasource-spec] (start-poller! conn datasource-spec {}))
  ([conn datasource-spec {:keys [revision event on-error initial_revision]
                          :or {initial_revision (System/currentTimeMillis)}}]
   (let [mode (poll-mode datasource-spec)
         stats (atom {:runs 0 :errors 0 :last_error nil :last_result nil})
         stop? (atom false)]
     (if (= mode :interval)
       (let [interval-ms (poll-interval-ms datasource-spec)
             revision-state (atom (long initial_revision))
             fut (future
                   (while (not @stop?)
                     (try
                       (let [result (ingest-datasource-once!
                                     conn
                                     datasource-spec
                                     {:revision (or revision (next-revision revision-state))
                                      :event event})]
                         (swap! stats (fn [s]
                                        (-> s
                                            (update :runs inc)
                                            (assoc :last_result result)
                                            (assoc :last_error nil)))))
                       (catch Exception e
                         (swap! stats (fn [s]
                                        (-> s
                                            (update :errors inc)
                                            (assoc :last_error (.getMessage e)))))
                         (when on-error
                           (on-error e datasource-spec))))
                     (Thread/sleep interval-ms)))]
         {:datasource (:id datasource-spec)
          :mode :interval
          :interval_ms interval-ms
          :stats stats
          :stop (fn []
                  (reset! stop? true)
                  (future-cancel fut)
                  true)
          :future fut})
       (let [result (ingest-datasource-once!
                     conn
                     datasource-spec
                     {:revision revision
                      :event event})]
         (swap! stats assoc :runs 1 :last_result result)
         {:datasource (:id datasource-spec)
          :mode :event
          :interval_ms nil
          :stats stats
          :stop (fn [] true)
          :future nil})))))

(defn start-all-pollers!
  "Start pollers for all datasource declarations in a compiled program."
  ([conn compiled] (start-all-pollers! conn compiled {}))
  ([conn compiled opts]
   (let [sources (mapv declaration->datasource-spec (datasource-declarations compiled))
         handles (mapv #(start-poller! conn % opts) sources)]
     {:sources (count sources)
      :handles handles})))

(defn stop-poller!
  [handle]
  ((:stop handle)))

(defn stop-all-pollers!
  [handles]
  (doseq [h handles]
    (stop-poller! h))
  true)
