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
    (spit output-path (exchange/encode-envelope envelope))
    (spit report-path (pr-str report))
    {:output output-path :report report-path :summary report}))

(defn- usage []
  (str "Usage: clojure -M:migrate [--allow-lossy] INPUT.zc OUTPUT.zilx REPORT.edn\n"
       "Strict lossless migration is the default."))

(defn -main [& args]
  (let [[strict? args] (if (= "--allow-lossy" (first args))
                         [false (rest args)]
                         [true args])]
    (if-not (= 3 (count args))
      (do (binding [*out* *err*] (println (usage))) (System/exit 2))
      (let [[input output report] args]
        (try
          (let [result (migrate-file! input output report {:strict? strict?})]
            (println (pr-str result)))
          (catch Exception error
            (binding [*out* *err*]
              (println (.getMessage error))
              (when-let [data (ex-data error)] (println (pr-str data))))
            (System/exit 1)))))))
