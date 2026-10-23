(ns zil.bridge.souffle-ci
  "Cross-check compiled ZIL query answers with the Souffle Datalog engine."
  (:require [clojure.set :as set]
            [zil.bridge.souffle :as souffle]
            [zil.core :as core]))

(defn compare-query-results
  "Compare complete query-name and row sets from two compiled-program engines."
  [zil-results souffle-results]
  (let [zil-names (set (keys zil-results))
        souffle-names (set (keys souffle-results))
        names (sort (into zil-names souffle-names))
        queries (mapv (fn [name]
                        (let [zil-rows (set (get-in zil-results [name :rows] []))
                              souffle-rows (set (get-in souffle-results [name :rows] []))
                              zil-vars (get-in zil-results [name :vars])
                              souffle-vars (get-in souffle-results [name :vars])]
                          {:query name
                           :ok (and (contains? zil-names name)
                                    (contains? souffle-names name)
                                    (= zil-vars souffle-vars)
                                    (= zil-rows souffle-rows))
                           :vars_match (= zil-vars souffle-vars)
                           :zil_rows (count zil-rows)
                           :souffle_rows (count souffle-rows)
                           :zil_only (vec (take 10 (sort (set/difference zil-rows souffle-rows))))
                           :souffle_only (vec (take 10 (sort (set/difference souffle-rows zil-rows))))}))
                      names)]
    {:ok (boolean (and (seq names)
                       (= zil-names souffle-names)
                       (every? :ok queries)))
     :query_count (count names)
     :zil_only_queries (vec (sort (set/difference zil-names souffle-names)))
     :souffle_only_queries (vec (sort (set/difference souffle-names zil-names)))
     :queries queries}))

(defn execute-parity
  "Execute a stratified ZIL model in both engines and compare its finite query answers."
  ([compiled] (execute-parity compiled {}))
  ([compiled opts]
   (let [zil-execution (core/execute-compiled compiled)
         souffle-execution (souffle/execute-with-souffle compiled opts)
         comparison (compare-query-results (:queries zil-execution)
                                           (:query-results souffle-execution))]
     (assoc comparison
            :zil_fact_count (count (:facts zil-execution))
            :souffle_version_checked (souffle/souffle-available?
                                      (or (:souffle-bin opts) "souffle"))))))
