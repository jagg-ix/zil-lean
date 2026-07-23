(ns zil.port.gate
  "Evaluate compiler coverage, runtime parity, and legacy retirement evidence."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as str]))

(def default-manifest "generated/zil/manifest.edn")
(def default-conformance "generated/zil/conformance.edn")
(def default-config-path "port-gate.edn")
(def default-output "generated/zil/port-gate.edn")

(def declaration-keywords
  ["SERVICE" "HOST" "DATASOURCE" "METRIC" "POLICY" "EVENT" "PROVIDER"
   "TM_ATOM" "LTS_ATOM" "REFINES" "CORRESPONDS" "PROOF_OBLIGATION"
   "FORMALIZATION_TARGET" "LANGUAGE_PROFILE" "GRAMMAR_PROFILE"
   "PARSER_ADAPTER" "DSL_PROFILE" "QUERY_PACK"])

(def default-config
  {:global {:min-compile-ratio 1.0
            :min-parity-ratio 1.0
            :min-exact-ratio 1.0
            :min-native-acceptance-ratio 1.0
            :max-mismatch 0
            :max-native-rejected 0
            :max-legacy-rejected 0
            :max-missing-conformance 0}
   :required-roots []
   :components
   {:tuple-frontend {:features #{:facts :usersets}
                     :min-sources 1}
    :attribute-frontend {:features #{:attributes}
                         :min-sources 1}
    :rule-query-runtime {:features #{:rules :queries}
                         :min-sources 1}
    :negation-runtime {:features #{:negation}
                       :min-sources 1}
    :macro-frontend {:features #{:macros}
                     :min-sources 1}
    :declaration-lowering {:features #{:declarations :tm-atoms :lts-atoms}
                           :min-sources 1}
    :library-corpus {:features #{}
                     :source-scope :all
                     :min-sources 1}
    :revision-causal {:features #{}
                      :source-scope :none
                      :min-sources 0
                      :evidence-files ["Zil/Core/Revision.lean"
                                       "Zil/Codec/Revision.lean"
                                       "Zil/Test/RevisionCausal.lean"
                                       "spec/revision-causal-v0.1.md"]}}})

(defn- canonical-path [value]
  (.getCanonicalPath (io/file value)))

(defn- ratio [numerator denominator]
  (if (zero? denominator) 0.0 (/ (double numerator) (double denominator))))

(defn- declaration-pattern []
  (re-pattern
   (str "(?im)^\\s*(?:" (str/join "|" declaration-keywords) ")\\s+")))

(defn source-features
  "Classify language constructs used by one source string."
  [source]
  (let [text (str source)
        facts? (boolean (re-find #"(?m)^\\s*[^/\\s][^\\n]*#[^\\n]*@[^\\n]*\\.\\s*$" text))
        attrs? (boolean (re-find #"(?m)\\[[^\\n]*=[^\\n]*\\]" text))
        usersets? (boolean (re-find #"@[^\\s\\[]+#[A-Za-z0-9_.:-]+" text))
        rules? (boolean (re-find #"(?im)^\\s*RULE\\s+" text))
        negation? (boolean (re-find #"(?i)(?:^|\\s)NOT\\s+" text))
        queries? (boolean (re-find #"(?im)^\\s*QUERY\\s+" text))
        macros? (boolean (re-find #"(?im)^\\s*(?:MACRO|USE)\\s+" text))
        declarations? (boolean (re-find (declaration-pattern) text))
        tm? (boolean (re-find #"(?im)^\\s*TM_ATOM\\s+" text))
        lts? (boolean (re-find #"(?im)^\\s*LTS_ATOM\\s+" text))]
    (cond-> #{}
      facts? (conj :facts)
      attrs? (conj :attributes)
      usersets? (conj :usersets)
      rules? (conj :rules)
      negation? (conj :negation)
      queries? (conj :queries)
      macros? (conj :macros)
      declarations? (conj :declarations)
      tm? (conj :tm-atoms)
      lts? (conj :lts-atoms))))

(def compile-success-statuses #{:compiled :checked})
(def parity-success-statuses #{:pass :both-rejected})
(def native-accepted-statuses #{:pass :mismatch :legacy-rejected})
(def exact-success-statuses #{:pass})

(defn- index-entries!
  [entries label]
  (reduce (fn [out entry]
            (let [source (canonical-path (:source entry))]
              (when (contains? out source)
                (throw (ex-info (str "Duplicate " label " source entry")
                                {:source source :label label})))
              (assoc out source entry)))
          (sorted-map)
          entries))

(defn- join-entry
  [source-reader conformance-index entry]
  (let [source (canonical-path (:source entry))
        conformance (get conformance-index source)
        status (or (:status conformance) :missing)
        features (try
                   (source-features (source-reader source))
                   (catch Exception _ #{}))]
    (sorted-map
     :source source
     :root (some-> (:root entry) canonical-path)
     :relative (:relative entry)
     :features features
     :compile-status (:status entry)
     :compile-ok (contains? compile-success-statuses (:status entry))
     :conformance-status status
     :parity-ok (contains? parity-success-statuses status)
     :exact-ok (contains? exact-success-statuses status)
     :native-accepted (contains? native-accepted-statuses status)
     :conformance-ok (boolean (:ok conformance)))))

(defn joined-corpus
  ([manifest conformance]
   (joined-corpus manifest conformance slurp))
  ([manifest conformance source-reader]
   (when-not (= "ZIL-LIBRARY-MANIFEST/1" (:schema manifest))
     (throw (ex-info "Unsupported library manifest schema"
                     {:schema (:schema manifest)})))
   (when-not (= "ZIL-CONFORMANCE/1" (:schema conformance))
     (throw (ex-info "Unsupported conformance schema"
                     {:schema (:schema conformance)})))
   (let [conformance-index (index-entries! (:entries conformance) "conformance")]
     (mapv #(join-entry source-reader conformance-index %)
           (:entries manifest)))))

(defn- status-count [records key value]
  (count (filter #(= value (get % key)) records)))

(defn summarize-records [records]
  (let [total (count records)
        compiled (count (filter :compile-ok records))
        parity (count (filter :parity-ok records))
        exact (count (filter :exact-ok records))
        native-accepted (count (filter :native-accepted records))
        mismatch (status-count records :conformance-status :mismatch)
        native-rejected (status-count records :conformance-status :native-rejected)
        legacy-rejected (status-count records :conformance-status :legacy-rejected)
        both-rejected (status-count records :conformance-status :both-rejected)
        missing (status-count records :conformance-status :missing)]
    (sorted-map
     :sources total
     :compiled compiled
     :compile-ratio (ratio compiled total)
     :parity parity
     :parity-ratio (ratio parity total)
     :exact exact
     :exact-ratio (ratio exact total)
     :native-accepted native-accepted
     :native-acceptance-ratio (ratio native-accepted total)
     :mismatch mismatch
     :native-rejected native-rejected
     :legacy-rejected legacy-rejected
     :both-rejected both-rejected
     :missing-conformance missing)))

(defn- threshold-failures [summary thresholds]
  (cond-> []
    (< (:compile-ratio summary) (:min-compile-ratio thresholds 0.0))
    (conj {:kind :compile-ratio
           :actual (:compile-ratio summary)
           :required (:min-compile-ratio thresholds)})

    (< (:parity-ratio summary) (:min-parity-ratio thresholds 0.0))
    (conj {:kind :parity-ratio
           :actual (:parity-ratio summary)
           :required (:min-parity-ratio thresholds)})

    (< (:exact-ratio summary) (:min-exact-ratio thresholds 0.0))
    (conj {:kind :exact-ratio
           :actual (:exact-ratio summary)
           :required (:min-exact-ratio thresholds)})

    (< (:native-acceptance-ratio summary)
       (:min-native-acceptance-ratio thresholds 0.0))
    (conj {:kind :native-acceptance-ratio
           :actual (:native-acceptance-ratio summary)
           :required (:min-native-acceptance-ratio thresholds)})

    (> (:mismatch summary) (:max-mismatch thresholds Long/MAX_VALUE))
    (conj {:kind :mismatch
           :actual (:mismatch summary)
           :allowed (:max-mismatch thresholds)})

    (> (:native-rejected summary)
       (:max-native-rejected thresholds Long/MAX_VALUE))
    (conj {:kind :native-rejected
           :actual (:native-rejected summary)
           :allowed (:max-native-rejected thresholds)})

    (> (:legacy-rejected summary)
       (:max-legacy-rejected thresholds Long/MAX_VALUE))
    (conj {:kind :legacy-rejected
           :actual (:legacy-rejected summary)
           :allowed (:max-legacy-rejected thresholds)})

    (> (:missing-conformance summary)
       (:max-missing-conformance thresholds Long/MAX_VALUE))
    (conj {:kind :missing-conformance
           :actual (:missing-conformance summary)
           :allowed (:max-missing-conformance thresholds)})))

(defn- component-records [records {:keys [features source-scope]}]
  (case source-scope
    :none []
    :all records
    (if (seq features)
      (filterv #(seq (set/intersection features (:features %))) records)
      records)))

(defn- feature-counts [records]
  (->> records
       (mapcat :features)
       frequencies
       (into (sorted-map))))

(defn- missing-feature-failures [records {:keys [features min-feature-sources]
                                          :or {min-feature-sources 1}}]
  (let [counts (feature-counts records)]
    (->> features
         sort
         (keep (fn [feature]
                 (let [actual (get counts feature 0)]
                   (when (< actual min-feature-sources)
                     {:kind :feature-coverage
                      :feature feature
                      :actual actual
                      :required min-feature-sources}))))
         vec)))

(defn- evidence-failures [file-exists? files]
  (->> files
       (remove file-exists?)
       sort
       (mapv (fn [path] {:kind :missing-evidence-file :path path}))))

(defn evaluate-component
  [records global-thresholds file-exists? [component component-config]]
  (let [selected (component-records records component-config)
        summary (summarize-records selected)
        thresholds (merge global-thresholds
                          (select-keys component-config
                                       [:min-compile-ratio
                                        :min-parity-ratio
                                        :min-exact-ratio
                                        :min-native-acceptance-ratio
                                        :max-mismatch
                                        :max-native-rejected
                                        :max-legacy-rejected
                                        :max-missing-conformance]))
        source-failures (if (< (:sources summary)
                               (:min-sources component-config 0))
                          [{:kind :minimum-sources
                            :actual (:sources summary)
                            :required (:min-sources component-config)}]
                          [])
        threshold-failures (if (= :none (:source-scope component-config))
                             []
                             (threshold-failures summary thresholds))
        feature-failures (missing-feature-failures records component-config)
        evidence-failures (evidence-failures file-exists?
                                               (:evidence-files component-config []))
        failures (vec (concat source-failures threshold-failures
                              feature-failures evidence-failures))]
    [component
     (sorted-map
      :retirable (empty? failures)
      :source-scope (or (:source-scope component-config) :features)
      :features (vec (sort (:features component-config)))
      :evidence-files (vec (sort (:evidence-files component-config [])))
      :summary summary
      :failures failures)]))

(defn- root-summaries [records]
  (->> records
       (group-by :root)
       (sort-by key)
       (map (fn [[root rows]] [root (summarize-records rows)]))
       (into (sorted-map))))

(defn- required-root-failures [manifest required-roots]
  (let [available (set (map canonical-path (:roots manifest)))]
    (->> required-roots
         (map canonical-path)
         (remove available)
         sort
         (mapv (fn [root] {:kind :missing-required-root :root root})))))

(defn evaluate
  "Evaluate one compiler manifest and conformance report against a gate config.

  Options accept injectable :source-reader and :file-exists? functions for tests."
  ([manifest conformance config]
   (evaluate manifest conformance config {}))
  ([manifest conformance config {:keys [source-reader file-exists?]
                                 :or {source-reader slurp
                                      file-exists? #(.exists (io/file %))}}]
   (let [config (merge-with merge default-config config)
         records (joined-corpus manifest conformance source-reader)
         global-summary (summarize-records records)
         global-thresholds (:global config)
         global-failures (vec (concat
                               (threshold-failures global-summary global-thresholds)
                               (required-root-failures manifest (:required-roots config))))
         components (->> (:components config)
                         (map #(evaluate-component records global-thresholds file-exists? %))
                         (into (sorted-map)))
         component-failures (->> components
                                 (keep (fn [[name result]]
                                         (when-not (:retirable result)
                                           {:kind :component-not-retirable
                                            :component name
                                            :failures (:failures result)})))
                                 vec)
         failures (vec (concat global-failures component-failures))]
     (sorted-map
      :schema "ZIL-PORT-GATE/1"
      :ok (empty? failures)
      :global global-summary
      :features (feature-counts records)
      :roots (root-summaries records)
      :components components
      :failures failures
      :records records))))

(defn- read-edn! [path]
  (let [file (io/file path)]
    (when-not (.exists file)
      (throw (ex-info "Required gate input does not exist" {:path path})))
    (edn/read-string (slurp file))))

(defn- write-report! [path report]
  (let [file (io/file path)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file (str (pr-str report) "\n"))))

(defn run-gate!
  [{:keys [manifest conformance config output]
    :or {manifest default-manifest
         conformance default-conformance
         config default-config-path
         output default-output}}]
  (let [manifest-data (read-edn! manifest)
        conformance-data (read-edn! conformance)
        config-data (if (.exists (io/file config))
                      (read-edn! config)
                      {})
        report (evaluate manifest-data conformance-data config-data)]
    (write-report! output report)
    report))

(def usage
  "zil-port-gate [--manifest FILE] [--conformance FILE] [--config FILE] [--output FILE]")

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:manifest default-manifest
                  :conformance default-conformance
                  :config default-config-path
                  :output default-output}]
    (if-not remaining
      options
      (let [arg (first remaining)]
        (case arg
          "--manifest" (recur (nnext remaining)
                              (assoc options :manifest (second remaining)))
          "--conformance" (recur (nnext remaining)
                                 (assoc options :conformance (second remaining)))
          "--config" (recur (nnext remaining)
                            (assoc options :config (second remaining)))
          "--output" (recur (nnext remaining)
                            (assoc options :output (second remaining)))
          "--help" (assoc options :help true)
          (throw (ex-info "Unknown port gate option" {:option arg})))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (run-gate! options)]
          (println (pr-str (select-keys report [:schema :ok :global :failures])))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)] (prn data)))
      (System/exit 2))))
