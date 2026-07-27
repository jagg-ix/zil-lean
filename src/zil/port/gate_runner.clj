(ns zil.port.gate-runner
  "Typed configuration merge and command wrapper for the port gate."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [zil.port.gate :as gate]))

(defn- canonical-path [value]
  (.getCanonicalPath (io/file value)))

(defn merge-config
  "Merge threshold maps and component maps while replacing scalar/vector fields."
  [config]
  (let [config (or config {})
        global (merge (:global gate/default-config)
                      (:global config))
        components (merge-with merge
                               (:components gate/default-config)
                               (:components config))]
    (-> gate/default-config
        (merge (dissoc config :global :components))
        (assoc :global global :components components))))

(defn- required-root-failures [manifest required-roots]
  (let [available (set (map canonical-path (:roots manifest)))]
    (->> required-roots
         (map canonical-path)
         (remove available)
         sort
         (mapv (fn [root] {:kind :missing-required-root :root root})))))

(defn evaluate
  "Evaluate reports with typed config merging and required-root checks."
  ([manifest conformance config]
   (evaluate manifest conformance config {}))
  ([manifest conformance config options]
   (let [merged (merge-config config)
         ;; The low-level evaluator receives only map-valued override fields.
         core-config {:global (:global merged)
                      :components (:components merged)}
         result (gate/evaluate manifest conformance core-config options)
         root-failures (required-root-failures manifest (:required-roots merged))
         failures (vec (concat (:failures result) root-failures))]
     (assoc result :ok (empty? failures) :failures failures))))

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
    :or {manifest gate/default-manifest
         conformance gate/default-conformance
         config gate/default-config-path
         output gate/default-output}}]
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

(defn- require-value [remaining option]
  (or (second remaining)
      (throw (ex-info "Missing option value" {:option option}))))

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:manifest gate/default-manifest
                  :conformance gate/default-conformance
                  :config gate/default-config-path
                  :output gate/default-output}]
    (if-not remaining
      options
      (let [arg (first remaining)]
        (case arg
          "--manifest" (recur (nnext remaining)
                              (assoc options :manifest
                                     (require-value remaining arg)))
          "--conformance" (recur (nnext remaining)
                                 (assoc options :conformance
                                        (require-value remaining arg)))
          "--config" (recur (nnext remaining)
                            (assoc options :config
                                   (require-value remaining arg)))
          "--output" (recur (nnext remaining)
                            (assoc options :output
                                   (require-value remaining arg)))
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
