(ns zil.runtime-ingest-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.core :as core]
            [zil.runtime.adapters.core :as ac]
            [zil.runtime.datascript :as zr]
            [zil.runtime.ingest :as ingest])
  (:import [com.sun.net.httpserver HttpHandler HttpServer]
           [java.net InetSocketAddress]))

(defn- start-json-server
  []
  (let [counter (atom 0)
        server (HttpServer/create (InetSocketAddress. "127.0.0.1" 0) 0)
        handler (reify HttpHandler
                  (handle [_ exchange]
                    (let [n (swap! counter inc)
                          body (str "{\"metric\":\"metric:latency\",\"value\":" n "}")
                          bytes (.getBytes body "UTF-8")]
                      (.add (.getResponseHeaders exchange) "Content-Type" "application/json")
                      (.sendResponseHeaders exchange 200 (alength bytes))
                      (with-open [os (.getResponseBody exchange)]
                        (.write os bytes)))))]
    (.createContext server "/metrics" handler)
    (.start server)
    {:server server
     :counter counter
     :url (str "http://127.0.0.1:" (.getPort (.getAddress server)) "/metrics")}))

(defn- wait-until
  [pred timeout-ms]
  (let [deadline (+ (System/currentTimeMillis) timeout-ms)]
    (loop []
      (cond
        (pred) true
        (> (System/currentTimeMillis) deadline) false
        :else (do (Thread/sleep 50)
                  (recur))))))

(deftest ingest-pipeline-smoke-test
  (let [tmp (java.io.File/createTempFile "zil-ingest" ".txt")
        _ (.deleteOnExit tmp)
        _ (spit tmp "alpha\nbeta\n")
        path (.getAbsolutePath tmp)
        program (str "MODULE ingest.demo.
DATASOURCE ds_rest [type=rest, mock_responses=[{:metric \"metric:latency\", :value 123}, {:metrics {:error_rate 0.01}}]].
DATASOURCE ds_file [type=file, path=\"" path "\", mode=lines].
DATASOURCE ds_cmd [type=command, command=\"printf 'hello-from-cmd'\"].
")
        compiled (core/compile-program program)
        conn (zr/make-conn)
        summary (ingest/ingest-all! conn compiled {:revision 7})
        snapshot (zr/facts-at-or-before @conn 7)
        relations (set (map :relation snapshot))]
    (is (every? (set (ac/supported-types)) [:rest :file :command]))
    (is (= 3 (:sources summary)))
    (is (pos? (:records summary)))
    (is (pos? (:facts summary)))
    (is (contains? relations :ingested_record))
    (is (contains? relations :observed_from))
    (is (some #(and (= "metric:latency" (:object %))
                    (= :observed_from (:relation %)))
              snapshot))
    (is (some #(= "datasource:ds_cmd" (:object %)) snapshot))))

(deftest ingest-file-and-command-formats-test
  (let [tmp-json (java.io.File/createTempFile "zil-ingest-fmt" ".json")
        tmp-yaml (java.io.File/createTempFile "zil-ingest-fmt" ".yaml")
        tmp-csv (java.io.File/createTempFile "zil-ingest-fmt" ".csv")
        _ (.deleteOnExit tmp-json)
        _ (.deleteOnExit tmp-yaml)
        _ (.deleteOnExit tmp-csv)
        _ (spit tmp-json (json/write-str [{:metric "metric:json_a" :value 11}
                                          {:metric "metric:json_b" :value 12}]))
        _ (spit tmp-yaml "- metric: metric:yaml_a\n  value: 21\n- metric: metric:yaml_b\n  value: 22\n")
        _ (spit tmp-csv "metric,value\nmetric:csv_a,31\nmetric:csv_b,32\n")
        path-json (.getAbsolutePath tmp-json)
        path-yaml (.getAbsolutePath tmp-yaml)
        path-csv (.getAbsolutePath tmp-csv)
        program (str "MODULE ingest.formats.demo.\n"
                     "DATASOURCE ds_json [type=file, path=\"" path-json "\", format=json].\n"
                     "DATASOURCE ds_yaml [type=file, path=\"" path-yaml "\", format=yaml].\n"
                     "DATASOURCE ds_csv [type=file, path=\"" path-csv "\", format=csv].\n"
                     "DATASOURCE ds_cmd_json [type=command, format=json, command=\"printf '{\\\"metric\\\":\\\"metric:cmd_json\\\",\\\"value\\\":55}'\"].\n")
        compiled (core/compile-program program)
        conn (zr/make-conn)
        summary (ingest/ingest-all! conn compiled {:revision 101})
        snapshot (zr/facts-at-or-before @conn 101)]
    (is (= 4 (:sources summary)))
    (is (some #(= "metric:json_a" (:object %)) snapshot))
    (is (some #(= "metric:yaml_a" (:object %)) snapshot))
    (is (some #(= "metric:csv_a" (:object %)) snapshot))
    (is (some #(= "metric:cmd_json" (:object %)) snapshot))))

(deftest rest-http-and-interval-polling-test
  (let [{:keys [server url counter]} (start-json-server)]
    (try
      (let [program (str "MODULE poll.demo.
DATASOURCE live [type=rest, url=\"" url "\", format=json, poll_mode=interval, poll_every_ms=120].
")
            compiled (core/compile-program program)
            conn (zr/make-conn)
            {:keys [handles]} (ingest/start-all-pollers! conn compiled {:initial_revision 100})
            converged? (wait-until
                        #(let [runs (-> handles first :stats deref :runs)]
                           (and (>= @counter 2)
                                (>= runs 2)))
                        3000)
            _ (ingest/stop-all-pollers! handles)
            snap (zr/facts-at-or-before @conn Long/MAX_VALUE)
            latest (first (filter #(and (= "metric:latency" (:object %))
                                        (= :observed_from (:relation %)))
                                  snap))
            polled (-> handles first :stats deref :runs)]
        (is converged?)
        (is (>= @counter 2))
        (is (>= polled 2))
        (is (some? latest))
        (is (>= (long (get-in latest [:attrs :value])) 2)))
      (finally
        (.stop ^HttpServer server 0)))))

(deftest cucumber-adapter-derives-causality-test
  (let [tmp (java.io.File/createTempFile "zil-cucumber" ".json")
        _ (.deleteOnExit tmp)
        payload
        [{:uri "features/auth.feature"
          :id "auth_feature"
          :name "Auth feature"
          :elements [{:id "login_ok"
                      :type "scenario"
                      :name "Login ok"
                      :steps [{:keyword "Given " :name "user opens page" :result {:status "passed" :duration 1000}}
                              {:keyword "When " :name "user enters password" :result {:status "passed" :duration 1200}}
                              {:keyword "Then " :name "dashboard is shown" :result {:status "passed" :duration 1400}}]}]}]
        _ (spit tmp (json/write-str payload))
        path (.getAbsolutePath tmp)
        program (str "MODULE cucumber.demo.
DATASOURCE cuc_run [type=cucumber, path=\"" path "\"].
")
        compiled (core/compile-program program)
        conn (zr/make-conn)
        summary (ingest/ingest-all! conn compiled {:revision 42})
        by-src (first (:by_source summary))
        db @conn
        edges (zr/q '[:find ?l ?r
                      :where
                      [?e :zil/event-left ?l]
                      [?e :zil/event-right ?r]]
                    db)
        vc-facts (zr/q '[:find ?event ?actor ?counter
                         :where
                         [?e :zil/object ?event]
                         [?e :zil/relation :vc_component]
                         [?e :zil/subject ?actor]
                         [?e :zil/attrs ?attrs]
                         [(get ?attrs :counter) ?counter]]
                       db)
        edge-events (set (map first edges))
        edge-targets (set (map second edges))]
    (is (= "datasource:cuc_run" (:datasource by-src)))
    (is (= :cucumber (:type by-src)))
    (is (= 3 (:records by-src)))
    (is (= 3 (:before_edges by-src)))
    (is (= 2 (:before_edges_explicit by-src)))
    (is (= 3 (:before_edges_derived by-src)))
    (is (= 3 (count vc-facts)))
    (is (= 3 (count edges)))
    (is (= 2 (count edge-events)))
    (is (= 2 (count edge-targets)))))
