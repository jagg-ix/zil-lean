(ns zil.bridge.workflow-runner
  (:gen-class)
  (:require [clojure.pprint :as pp]
            [zil.bridge.workflow-lean :as workflow]))

(def usage
  "zil-workflow <store.sqlite> <module> <output.lean> <namespace> <as_of_epoch>")

(defn -main [& args]
  (try
    (if-not (= 5 (count args))
      (do
        (binding [*out* *err*] (println usage))
        (System/exit 2))
      (let [[db-path module output namespace as-of-text] args
            as-of (Long/parseLong as-of-text)
            report (workflow/export-workflow!
                    db-path module output namespace as-of
                    {:verify-generated true})]
        (pp/pprint report)
        (System/exit (if (:ok report) 0 1))))
    (catch NumberFormatException _
      (binding [*out* *err*] (println "as_of_epoch must be an integer"))
      (System/exit 2))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
