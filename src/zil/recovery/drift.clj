(ns zil.recovery.drift
  "Bounded context drift analysis and mutation preflight."
  (:require [clojure.data.json :as json]
            [clojure.set :as set]
            [zil.store.sqlite :as store]))

(defn- query-one [conn sql parameters]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (with-open [rows (.executeQuery statement)]
      (when (.next rows) (.getString rows 1)))))

(defn- snapshot-facts [conn revision]
  (when-let [text (query-one conn "SELECT facts_json FROM snapshots WHERE revision=? AND valid=1" [revision])]
    (json/read-str text)))

(defn- batch-id [conn revision]
  (some-> (query-one conn "SELECT batch_id FROM batches WHERE revision=?" [revision])
          Long/parseLong))

(defn- changed-declarations [conn module from-id to-id]
  (with-open [statement (.prepareStatement conn "SELECT DISTINCT o.declaration FROM operations o JOIN batches b ON b.batch_id=o.batch_id WHERE b.module=? AND b.batch_id>? AND b.batch_id<=? ORDER BY o.declaration")]
    (.setString statement 1 module)
    (.setLong statement 2 from-id)
    (.setLong statement 3 to-id)
    (with-open [rows (.executeQuery statement)]
      (loop [out []]
        (if (.next rows) (recur (conj out (.getString rows 1))) out)))))

(defn- fact-set [facts]
  (set (map (juxt #(get % "object") #(get % "relation") #(get % "subject")) facts)))

(defn- reverse-dependencies [facts]
  (reduce (fn [index fact]
            (if (= "depends_on" (get fact "relation"))
              (update index (get fact "subject") (fnil conj (sorted-set))
                      (get fact "object"))
              index))
          (sorted-map) facts))

(defn- bounded-impact [facts seeds max-depth max-nodes]
  (let [reverse-index (reverse-dependencies facts)]
    (loop [depth 0 frontier (sorted-set) visited (set seeds) impacted (sorted-set)]
      (let [frontier (if (zero? depth) (into (sorted-set) seeds) frontier)]
        (cond
          (empty? frontier) {:nodes (vec impacted) :complete true :depth depth}
          (>= depth max-depth) {:nodes (vec impacted) :complete false :depth depth}
          :else
          (let [candidates (->> frontier
                                (mapcat #(get reverse-index % []))
                                (remove visited)
                                set
                                sort)
                capacity (- max-nodes (count impacted))
                accepted (take (max 0 capacity) candidates)
                truncated? (> (count candidates) (count accepted))
                next-impacted (into impacted accepted)]
            (if (or truncated? (>= (count next-impacted) max-nodes))
              {:nodes (vec next-impacted) :complete false :depth (inc depth)}
              (recur (inc depth) (into (sorted-set) accepted)
                     (into visited accepted) next-impacted))))))))

(defn analyze-drift
  ([db-path module requested-revision]
   (analyze-drift db-path module requested-revision {:max-depth 8 :max-nodes 1000}))
  ([db-path module requested-revision {:keys [max-depth max-nodes]
                                       :or {max-depth 8 max-nodes 1000}}]
   (with-open [conn (store/initialize! (store/connect db-path))]
     (let [current (store/current-revision conn module)]
       (when-not current
         (throw (ex-info "No current snapshot for module"
                         {:code :context-incomplete :module module})))
       (if (= requested-revision current)
         {:ok true :status :current :code nil :module module
          :requested_revision requested-revision :current_revision current
          :changed_declarations [] :affected_dependents []
          :complete true :recovery_plan []}
         (let [from-id (batch-id conn requested-revision)
               to-id (batch-id conn current)]
           (when-not from-id
             (throw (ex-info "Requested context revision is unknown"
                             {:code :context-incomplete :requested requested-revision})))
           (let [requested-module (query-one conn "SELECT module FROM batches WHERE revision=?"
                                             [requested-revision])]
             (when-not (= module requested-module)
               (throw (ex-info "Requested revision belongs to a different module"
                               {:code :revision-conflict :module module
                                :requested-module requested-module
                                :requested requested-revision}))))
           (when (> from-id to-id)
             (throw (ex-info "Requested context revision is not an ancestor of current"
                             {:code :revision-conflict :requested requested-revision
                              :current current})))
           (let [before (snapshot-facts conn requested-revision)
                 after (snapshot-facts conn current)
                 before-set (fact-set before) after-set (fact-set after)
                 changed (changed-declarations conn module from-id to-id)
                 seeds (map #(str "lean:" %) changed)
                 impact (bounded-impact after seeds max-depth max-nodes)]
             {:ok true :status :stale :code :context-stale :module module
              :requested_revision requested-revision :current_revision current
              :added_fact_count (count (set/difference after-set before-set))
              :removed_fact_count (count (set/difference before-set after-set))
              :changed_declarations changed
              :affected_dependents (:nodes impact)
              :impact_depth (:depth impact)
              :complete (:complete impact)
              :recovery_plan
              [{:step 1 :action :discard_local_assumptions}
               {:step 2 :action :load_revision :revision current}
               {:step 3 :action :invalidate_dependents :targets (:nodes impact)
                :complete (:complete impact)}
               {:step 4 :action :revalidate_obligations}
               {:step 5 :action :run_preflight}]})))))))

(defn mutation-preflight [db-path module requested-revision]
  (let [integrity (store/verify-store db-path module)]
    (cond
      (not (:ok integrity))
      {:allowed false :code :recovery-required :reason :store-replay-mismatch
       :module module :requested_revision requested-revision
       :current_revision (:revision integrity)}

      (not= requested-revision (:revision integrity))
      {:allowed false :code :context-stale :reason :revision-mismatch
       :module module :requested_revision requested-revision
       :current_revision (:revision integrity)}

      :else
      {:allowed true :code nil :module module :requested_revision requested-revision
       :current_revision (:revision integrity) :store_integrity true})))
