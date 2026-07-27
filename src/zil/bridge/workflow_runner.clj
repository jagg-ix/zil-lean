(ns zil.bridge.workflow-runner
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.pprint :as pp]
            [zil.bridge.workflow-lean :as workflow]
            [zil.release.attestation :as release]))

(def workflow-format "zil.workflow-verification.v0.1")

(defn- canonical-key [key]
  (if (keyword? key) (name key) (str key)))

(defn- canonical-value [item]
  (cond
    (map? item) (into (sorted-map)
                      (map (fn [[key value]]
                             [(canonical-key key) (canonical-value value)]))
                      item)
    (vector? item) (mapv canonical-value item)
    (sequential? item) (mapv canonical-value item)
    (keyword? item) (name item)
    :else item))

(defn workflow-document [report]
  (let [output (:output report)
        output-file (io/file output)]
    (when-not (.isFile output-file)
      (throw (ex-info "Generated workflow module does not exist"
                      {:output output})))
    (-> report
        (assoc :format workflow-format
               :output_sha256 (release/file-sha256 output-file))
        canonical-value)))

(defn write-report! [path report]
  (when-let [parent (.getParentFile (io/file path))] (.mkdirs parent))
  (let [document (workflow-document report)]
    (spit path (str (json/write-str document :escape-slash false) "\n"))
    document))

(def usage
  (str "zil-workflow <store.sqlite> <module> <output.lean> <namespace> "
       "<as_of_epoch> [report.json]"))

(defn -main [& args]
  (try
    (if-not (contains? #{5 6} (count args))
      (do
        (binding [*out* *err*] (println usage))
        (System/exit 2))
      (let [[db-path module output namespace as-of-text report-path] args
            as-of (Long/parseLong as-of-text)
            report (workflow/export-workflow!
                    db-path module output namespace as-of
                    {:verify-generated true})]
        (if report-path
          (println (json/write-str (write-report! report-path report)
                                   :escape-slash false))
          (pp/pprint report))
        (System/exit (if (:ok report) 0 1))))
    (catch NumberFormatException _
      (binding [*out* *err*] (println "as_of_epoch must be an integer"))
      (System/exit 2))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
