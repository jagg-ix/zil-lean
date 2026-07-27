(ns zil.evaluation.cli
  "CLI for evidence-driven runtime architecture evaluation."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.evaluation.architecture :as architecture]))

(def default-model "architecture/runtime-evaluation.edn")

(def usage
  (str "zil-evaluate [--model FILE] [--measurements FILE] [--output FILE|-]\n"
       "Measurement files contain an EDN vector of ZIL runtime measurements."))

(defn- value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "missing evaluation option value"
                      {:kind :invalid-command :option flag}))))

(defn- parse-options [args]
  (loop [remaining (seq args)
         options {:model default-model :measurements nil :output "-"}]
    (if-not remaining
      options
      (case (first remaining)
        "--model" (recur (nnext remaining)
                         (assoc options :model (value! remaining "--model")))
        "--measurements" (recur (nnext remaining)
                                (assoc options :measurements
                                       (value! remaining "--measurements")))
        "--output" (recur (nnext remaining)
                          (assoc options :output (value! remaining "--output")))
        "--help" (assoc options :help true)
        "-h" (assoc options :help true)
        (throw (ex-info "unknown evaluation option"
                        {:kind :invalid-command :option (first remaining)}))))))

(defn- write-output! [path value]
  (let [text (str (pr-str value) "\n")]
    (if (or (nil? path) (= path "-"))
      (print text)
      (let [file (io/file path)]
        (when-let [parent (.getParentFile file)] (.mkdirs parent))
        (spit file text)))))

(defn -main [& args]
  (try
    (let [{:keys [model measurements output help]} (parse-options args)]
      (if help
        (println usage)
        (let [model-value (architecture/load-edn model)
              measurement-values (if measurements
                                   (architecture/load-edn measurements)
                                   [])
              report (architecture/evaluate model-value measurement-values)]
          (write-output! output report)
          (System/exit
           (if (pos? (get-in report [:summary :candidate-change])) 1 0)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
