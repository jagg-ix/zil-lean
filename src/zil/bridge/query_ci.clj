(ns zil.bridge.query-ci
  "Helpers to run DSL-aware query CI over file-or-directory model paths."
  (:require [zil.core :as core]
            [zil.model-exchange :as mx]
            [zil.preprocess :as zp]))

(defn- compact-report
  [report include-rows?]
  (if include-rows?
    report
    (dissoc report :queries)))

(defn- run-query-ci-file
  [path {:keys [profile include_rows lib-dir]}]
  (let [opts (cond-> {}
               profile (assoc :profile profile)
               (contains? #{true false} include_rows) (assoc :include_rows include_rows))]
    (try
      (assoc (core/query-ci-file path opts)
             :file path
             :preprocessed false)
      (catch clojure.lang.ExceptionInfo e
        (if (re-find #"Unknown macro invocation" (.getMessage e))
          (let [pp (zp/preprocess-model
                    path
                    (cond-> {}
                      lib-dir (assoc :lib-dir lib-dir)))
                report (core/query-ci-program (:text pp) opts)]
            (assoc report
                   :file path
                   :preprocessed true
                   :preprocess (dissoc pp :text)))
          (throw e))))))

(defn run-query-ci-path
  "Run `query-ci` over one file or all `.zc` files in a directory.

  Options:
  - :profile       optional DSL profile name filter
  - :include_rows  include query rows in per-file reports (default: false)
  - :lib-dir       optional preprocessor lib dir for macro fallback"
  ([path]
   (run-query-ci-path path {}))
  ([path {:keys [profile include_rows]
          :or {include_rows false}
          :as opts}]
   (let [files (mx/collect-zc-files path)]
     (when (empty? files)
       (throw (ex-info "No .zc files found for query-ci path"
                       {:path path})))
     (let [reports (mapv #(run-query-ci-file % opts) files)
           failed (->> reports
                       (filter (complement :ok))
                       (mapv #(select-keys (compact-report % include_rows)
                                           [:file :ok :selected_dsl_profiles :selected_query_packs :selected_queries :checks])))
           ok? (empty? failed)]
       {:ok ok?
        :path path
        :profile profile
        :file_count (count files)
        :files files
        :reports (mapv #(compact-report % include_rows) reports)
        :failed failed
        :selected_dsl_profiles (->> reports
                                    (mapcat :selected_dsl_profiles)
                                    distinct
                                    sort
                                    vec)
        :selected_query_packs (->> reports
                                   (mapcat :selected_query_packs)
                                   distinct
                                   sort
                                   vec)}))))
