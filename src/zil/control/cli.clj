(ns zil.control.cli
  "Command-line entry point for the formal Clojure control plane."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.control.command :as command]
            [zil.control.runtime :as runtime]))

(def usage
  (str "zil-control <operation> <input-path> [operation-arguments...]\n"
       "Operations: parse, compile, expand, conformance, query, authorize, impact, recovery-audit"))

(defn -main [& args]
  (try
    (let [[operation input-path & arguments] args]
      (when (or (str/blank? operation) (str/blank? input-path))
        (throw (ex-info usage {:kind :invalid-command})))
      (let [control-plane (runtime/start! {:pool-size 1})
            response
            (try
              (command/execute! control-plane operation input-path arguments)
              (finally
                (runtime/stop! control-plane)))]
        (println (json/write-str response))
        (System/exit (if (= "ok" (:status response)) 0 1))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
