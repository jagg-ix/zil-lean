(ns zil.interop-test
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.core :as core]
            [zil.interop :as zi]))

(deftest import-data-to-zil-test
  (let [tmp-json (java.io.File/createTempFile "zil-interop" ".json")
        _ (.deleteOnExit tmp-json)
        _ (spit tmp-json (json/write-str [{:metric "metric:latency" :value 9}
                                          {:metric "metric:error_rate" :value 0.02}]))
        report (zi/import-data->zil (.getAbsolutePath tmp-json)
                                    {:module-name "interop.import.test"
                                     :format :json})]
    (is (:ok report))
    (is (= :json (:format report)))
    (is (= 2 (:records report)))
    (is (re-find #"MODULE interop.import.test\." (:text report)))
    (is (re-find #"entity:interop_record" (:text report)))
    (let [result (core/execute-program (:text report))]
      (is (seq (:facts result))))))

(deftest export-model-data-test
  (let [tmp-model (java.io.File/createTempFile "zil-export" ".zc")
        _ (.deleteOnExit tmp-model)
        _ (spit tmp-model (str "MODULE interop.export.demo.\n"
                               "service:api_gateway#state@value:healthy.\n"
                               "QUERY service_states:\n"
                               "FIND ?svc ?state WHERE ?svc#state@?state.\n"))]
    (testing "JSON export for all queries"
      (let [report (zi/export-model-data (.getAbsolutePath tmp-model)
                                         {:format :json :source "queries"})]
        (is (:ok report))
        (is (= :json (:format report)))
        (is (re-find #"service_states" (:text report)))))

    (testing "YAML export for one query"
      (let [report (zi/export-model-data (.getAbsolutePath tmp-model)
                                         {:format :yaml :source "service_states"})]
        (is (:ok report))
        (is (re-find #"state:" (:text report)))))

    (testing "CSV export for one query"
      (let [report (zi/export-model-data (.getAbsolutePath tmp-model)
                                         {:format :csv :source "service_states"})]
        (is (:ok report))
        (is (str/includes? (:text report) "svc"))
        (is (str/includes? (:text report) "value:healthy"))))

    (testing "CSV export rejects all-queries source"
      (is (thrown-with-msg?
           clojure.lang.ExceptionInfo
           #"CSV export requires a single tabular source"
           (zi/export-model-data (.getAbsolutePath tmp-model)
                                 {:format :csv :source "queries"}))))))
