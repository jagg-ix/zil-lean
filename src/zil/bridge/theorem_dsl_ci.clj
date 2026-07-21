(ns zil.bridge.theorem-dsl-ci
  "One-shot theorem DSL pipeline using macro-based sugar over canonical ZIL facts.

  Pipeline:
  1) preprocess model (loads macro DSL from lib/)
  2) execute preprocessed model to compute operator summary
  3) theorem bridge generation
  4) lts/constraint checks
  5) TLA+/Lean exports
  6) write summary JSON"
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.bridge.lean4 :as bl]
            [zil.bridge.theorem :as bth]
            [zil.bridge.tla :as bt]
            [zil.core :as core]
            [zil.model-exchange :as mx]
            [zil.preprocess :as zp]))

(defn- token->name
  [v]
  (cond
    (string? v) v
    (keyword? v) (name v)
    (symbol? v) (name v)
    :else (str v)))

(defn- unprefix
  [prefix s]
  (let [txt (token->name s)]
    (if (str/starts-with? txt prefix)
      (subs txt (count prefix))
      txt)))

(defn- file-stem
  [path]
  (let [name (.getName (io/file path))
        idx (.lastIndexOf name ".")]
    (if (pos? idx)
      (subs name 0 idx)
      name)))

(defn- ensure-dir!
  [path]
  (let [dir (io/file path)]
    (.mkdirs dir)
    (.getAbsolutePath dir)))

(defn- parent-chain
  [^java.io.File dir]
  (take-while some? (iterate #(.getParentFile ^java.io.File %) dir)))

(defn- resolve-default-theorem-lib-dir
  [model-path]
  (let [mf (-> model-path io/file .getAbsoluteFile)
        start (if (.isDirectory mf) mf (.getParentFile mf))]
    (some (fn [^java.io.File d]
            (let [cand (io/file d "libsets" "theorem-dsl-ci")]
              (when (.isDirectory cand)
                (.getAbsolutePath cand))))
          (parent-chain start))))

(defn- truthy-fact?
  [subject]
  (= "value:true" (token->name subject)))

(defn- theorem-fact?
  [{:keys [object]}]
  (str/starts-with? (token->name object) "theorem:"))

(defn- theorem-id
  [object]
  (unprefix "theorem:" object))

(defn- sort-rows
  [ks rows]
  (vec (sort-by (apply juxt ks) rows)))

(defn- status-rows
  [facts]
  (->> facts
       (filter #(and (= :status (:relation %))
                     (theorem-fact? %)))
       (map (fn [{:keys [object subject]}]
              {:theorem (theorem-id object)
               :status (str/upper-case (unprefix "value:" subject))}))
       distinct
       (sort-rows [:theorem :status])))

(defn- missing-dependency-rows
  [facts]
  (->> facts
       (filter #(and (= :conditional_on (:relation %))
                     (theorem-fact? %)))
       (map (fn [{:keys [object subject]}]
              {:theorem (theorem-id object)
               :dependency (token->name subject)}))
       distinct
       (sort-rows [:theorem :dependency])))

(defn- break-root-rows
  [facts]
  (->> facts
       (filter #(and (= :is_break_root (:relation %))
                     (truthy-fact? (:subject %))))
       (map (fn [{:keys [object]}]
              {:node (token->name object)}))
       distinct
       (sort-rows [:node])))

(defn- impact-rows
  [facts]
  (->> facts
       (filter #(and (= :impacted_by_root (:relation %))
                     (theorem-fact? %)))
       (map (fn [{:keys [object subject]}]
              {:theorem (theorem-id object)
               :root (token->name subject)}))
       distinct
       (sort-rows [:theorem :root])))

(defn- status-counts
  [statuses]
  (reduce (fn [m {:keys [status]}]
            (update m status (fnil inc 0)))
          {"PROVED" 0
           "CONDITIONAL" 0
           "BROKEN" 0
           "WEAK" 0}
          statuses))

(defn- operator-summary
  [facts]
  (let [statuses (status-rows facts)
        missing (missing-dependency-rows facts)
        roots (break-root-rows facts)
        impact (impact-rows facts)]
    {:status_counts (status-counts statuses)
     :statuses statuses
     :missing_dependencies missing
     :break_roots roots
     :impact_set impact}))

(defn- json-safe
  [x]
  (cond
    (map? x)
    (into {}
          (map (fn [[k v]]
                 [(if (keyword? k) (name k) (str k))
                  (json-safe v)]))
          x)

    (vector? x) (mapv json-safe x)
    (set? x) (mapv json-safe (sort (map pr-str x)))
    (seq? x) (mapv json-safe x)
    (keyword? x) (name x)
    (symbol? x) (name x)
    :else x))

(defn- write-json!
  [path payload]
  (let [out-file (io/file path)
        parent (.getParentFile out-file)]
    (when parent
      (.mkdirs parent))
    (spit out-file (json/write-str (json-safe payload))))
  path)

(defn- assert-ok!
  [stage report]
  (when-not (:ok report)
    (throw (ex-info (str "Theorem DSL CI stage failed: " (name stage))
                    {:stage stage
                     :report report})))
  report)

(defn run-theorem-dsl-ci
  "Run theorem operations through macro-based DSL pipeline.

  Required:
  - model must be a .zc file that uses DSL macros from lib/theorem-dsl-macros.zc

  Options:
  - :out-dir         output directory (default /tmp)
  - :lib-dir         preprocess override for lib directory
  - :bridge-module   theorem bridge module override
  - :tla-module      TLA module override
  - :lean-namespace  Lean namespace override
  - :summary-json    summary JSON output path override"
  ([model-path]
   (run-theorem-dsl-ci model-path {}))
  ([model-path {:keys [out-dir lib-dir bridge-module tla-module lean-namespace summary-json]}]
   (let [mf (io/file model-path)]
     (when-not (.exists mf)
       (throw (ex-info "Theorem DSL CI model path does not exist" {:path model-path})))
     (when-not (.isFile mf)
       (throw (ex-info "Theorem DSL CI expects a model file path" {:path model-path})))
     (let [out-dir* (ensure-dir! (or out-dir "/tmp"))
           stem (file-stem model-path)
           pre-zc (.getAbsolutePath (io/file out-dir* (str stem ".dsl.pre.zc")))
           bridge-zc (.getAbsolutePath (io/file out-dir* (str stem ".dsl.bridge.zc")))
           bridge-tla (.getAbsolutePath (io/file out-dir* (str stem ".dsl.bridge.tla")))
           bridge-lean (.getAbsolutePath (io/file out-dir* (str stem ".dsl.bridge.lean")))
           summary-json* (or summary-json
                             (.getAbsolutePath (io/file out-dir* (str stem ".dsl.summary.json"))))
           lib-dir* (or lib-dir (resolve-default-theorem-lib-dir model-path))
           preprocess-report (zp/preprocess-model
                              model-path
                              (cond-> {:output-path pre-zc}
                                lib-dir* (assoc :lib-dir lib-dir*)))
           execution-report (core/execute-file pre-zc)
           op-summary (operator-summary (:facts execution-report))
           bridge-report (bth/theorem-contracts->bridge
                          pre-zc
                          (cond-> {:output-path bridge-zc}
                            bridge-module (assoc :module-name bridge-module)))
           lts-report (mx/check-bundle bridge-zc {:profile :lts})
           constraint-report (mx/check-bundle bridge-zc {:profile :constraint})
           _ (assert-ok! :lts-check lts-report)
           _ (assert-ok! :constraint-check constraint-report)
           tla-report (bt/export-lts->tla
                       bridge-zc
                       (cond-> {:output-path bridge-tla}
                         tla-module (assoc :module-name tla-module)))
           lean-report (bl/export-lts->lean4
                        bridge-zc
                        (cond-> {:output-path bridge-lean}
                          lean-namespace (assoc :namespace lean-namespace)))
           report {:ok true
                   :path model-path
                   :out_dir out-dir*
                   :artifacts {:preprocessed_zc pre-zc
                               :bridge_zc bridge-zc
                               :bridge_tla bridge-tla
                               :bridge_lean bridge-lean
                               :summary_json summary-json*}
                   :preprocess (dissoc preprocess-report :text)
                   :execution {:module (:module execution-report)
                               :fact_count (count (:facts execution-report))
                               :query_names (sort (keys (:queries execution-report)))}
                   :operator_summary op-summary
                   :bridge (dissoc bridge-report :text)
                   :checks {:lts lts-report
                            :constraint constraint-report}
                   :exports {:tla (dissoc tla-report :text)
                             :lean (dissoc lean-report :text)}}]
       (write-json! summary-json* report)
       report))))
