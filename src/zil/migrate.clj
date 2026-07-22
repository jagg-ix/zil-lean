(ns zil.migrate
  "Automated migration from legacy .zc source to canonical ZILX/1 snapshots."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.exchange :as exchange]
            [zil.relational-ir :as ir]))

(defn- atom-vars [atom]
  (->> [(:object atom) (:subject atom)]
       (filter core/variable-token?)
       (map #(subs % 1))
       distinct
       vec))

(defn- canonical-atom [atom]
  (ir/from-legacy-atom atom))

(defn- unsupported-atom-issues [context atom]
  (cond-> []
    (:neg? atom)
    (conj {:kind :unsupported-negation :context context :atom atom})

    (seq (:attrs atom))
    (conj {:kind :dropped-attributes :context context :attrs (:attrs atom)})))

(defn- migrate-rule [rule]
  (let [issues (vec (mapcat #(unsupported-atom-issues (:name rule) %)
                            (concat (:if rule) (:then rule))))
        positive-premises (remove :neg? (:if rule))
        variables (->> (concat positive-premises (:then rule))
                       (mapcat atom-vars)
                       distinct
                       vec)
        premises (mapv canonical-atom positive-premises)]
    {:rules
     (mapv (fn [index head]
             (ir/canonical-rule
              {:name (if (= 1 (count (:then rule)))
                       (:name rule)
                       (str (:name rule) "__head_" (inc index)))
               :variables variables
               :premises premises
               :conclusion (canonical-atom head)
               :trust :graph-derived
               :source {:frontend "legacy-zc"}}))
           (range)
           (:then rule))
     :issues issues}))

(defn migrate-text
  "Parse legacy ZIL source and return {:envelope ... :report ...}.

  Strict mode rejects any lossy or unsupported construct. Non-strict mode emits
  canonical supported knowledge and records every loss in the report."
  ([text] (migrate-text text {}))
  ([text {:keys [strict? knowledge-revision profile-name profile-version source]
          :or {strict? true knowledge-revision 0
               profile-name "zil.profile.research" profile-version "0.1"}}]
   (let [program (core/parse-program text)
         fact-issues (vec (mapcat #(unsupported-atom-issues :fact %) (:facts program)))
         migrated-rules (mapv migrate-rule (:rules program))
         query-issues (mapv (fn [query]
                              {:kind :unsupported-query
                               :query (:name query)
                               :message "queries are not persisted in ZILX/1"})
                            (:queries program))
         issues (vec (concat fact-issues
                             (mapcat :issues migrated-rules)
                             query-issues))
         blocking (filterv #(contains? #{:unsupported-negation
                                         :dropped-attributes
                                         :unsupported-query}
                                       (:kind %))
                           issues)]
     (when (and strict? (seq blocking))
       (throw (ex-info "Legacy migration would be lossy" {:issues blocking})))
     (let [facts (->> (:facts program)
                      (remove :neg?)
                      (mapv canonical-atom))
           rules (vec (mapcat :rules migrated-rules))
           envelope {:schema-version "1"
                     :knowledge-revision knowledge-revision
                     :profile-name profile-name
                     :profile-version profile-version
                     :facts facts
                     :rules rules}]
       {:envelope envelope
        :report {:source source
                 :module (:module program)
                 :facts-read (count (:facts program))
                 :facts-emitted (count facts)
                 :rules-read (count (:rules program))
                 :rules-emitted (count rules)
                 :queries-skipped (count (:queries program))
                 :declarations-lowered (count (:declarations program))
                 :issues issues
                 :lossless? (empty? issues)}}))))

(defn migrate-file!
  [input-path output-path report-path options]
  (let [{:keys [envelope report]}
        (migrate-text (slurp input-path) (assoc options :source input-path))]
    (io/make-parents output-path)
    (io/make-parents report-path)
    (spit output-path (exchange/encode-envelope envelope))
    (spit report-path (pr-str report))
    {:input input-path :output output-path :report report-path :summary report}))

(defn- relative-path [root file]
  (let [root-path (.toPath (.getCanonicalFile (io/file root)))
        file-path (.toPath (.getCanonicalFile (io/file file)))]
    (str (.relativize root-path file-path))))

(defn- replace-extension [path extension]
  (str/replace path #"(?i)\.zc$" extension))

(defn migrate-tree!
  "Recursively migrate every `.zc` file below `input-root`.

  Output snapshots and EDN reports preserve the source directory structure.
  A manifest is always written, even when individual files fail. In strict mode
  the function throws after writing the manifest if any file failed."
  [input-root output-root options]
  (let [files (->> (file-seq (io/file input-root))
                   (filter #(.isFile %))
                   (filter #(str/ends-with? (str/lower-case (.getName %)) ".zc"))
                   (sort-by #(.getCanonicalPath %)))
        results (mapv
                 (fn [file]
                   (let [relative (relative-path input-root file)
                         snapshot (str (io/file output-root (replace-extension relative ".zilx")))
                         report (str (io/file output-root (replace-extension relative ".migration.edn")))]
                     (try
                       (assoc (migrate-file! (str file) snapshot report options) :status :ok)
                       (catch Exception error
                         {:input (str file)
                          :output snapshot
                          :report report
                          :status :error
                          :message (.getMessage error)
                          :data (ex-data error)}))))
                 files)
        manifest {:input-root input-root
                  :output-root output-root
                  :strict? (get options :strict? true)
                  :files (count files)
                  :migrated (count (filter #(= :ok (:status %)) results))
                  :failed (count (filter #(= :error (:status %)) results))
                  :results results}
        manifest-path (str (io/file output-root "migration-manifest.edn"))]
    (io/make-parents manifest-path)
    (spit manifest-path (pr-str manifest))
    (when (and (get options :strict? true) (pos? (:failed manifest)))
      (throw (ex-info "One or more legacy files failed migration"
                      {:manifest manifest-path :failed (:failed manifest)})))
    manifest))

(defn- usage []
  (str "Usage:\n"
       "  clojure -M:migrate [--allow-lossy] INPUT.zc OUTPUT.zilx REPORT.edn\n"
       "  clojure -M:migrate [--allow-lossy] --tree INPUT_DIR OUTPUT_DIR\n"
       "Strict lossless migration is the default."))

(defn -main [& raw-args]
  (let [[strict? args] (if (= "--allow-lossy" (first raw-args))
                         [false (rest raw-args)]
                         [true raw-args])]
    (try
      (cond
        (and (= "--tree" (first args)) (= 3 (count args)))
        (let [[_ input output] args]
          (println (pr-str (migrate-tree! input output {:strict? strict?}))))

        (= 3 (count args))
        (let [[input output report] args]
          (println (pr-str (migrate-file! input output report {:strict? strict?}))))

        :else
        (do (binding [*out* *err*] (println (usage))) (System/exit 2)))
      (catch Exception error
        (binding [*out* *err*]
          (println (.getMessage error))
          (when-let [data (ex-data error)] (println (pr-str data))))
        (System/exit 1)))))
