(ns zil.control.conformance
  "Control-plane entry point for differential Clojure/Lean conformance."
  (:gen-class)
  (:require [zil.control.adapters :as adapters]
            [zil.control.runtime :as runtime]
            [zil.port.conformance :as conformance]
            [zil.port.library :as library]))

(defn run-suite! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (conformance/run-suite!
      (assoc options
             :command [adapters/adapter-command]
             :runner (adapters/vector-runner control-plane))))))

(defn- value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "missing conformance option value"
                      {:kind :invalid-command :option flag}))))

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:roots [] :output conformance/default-output}]
    (if-not remaining
      (update options :roots #(if (seq %) % library/default-roots))
      (case (first remaining)
        "--root" (recur (nnext remaining)
                        (update options :roots conj (value! remaining "--root")))
        "--output" (recur (nnext remaining)
                          (assoc options :output (value! remaining "--output")))
        "--lib" (recur (nnext remaining)
                       (assoc options :lib-dir (value! remaining "--lib")))
        "--help" (assoc options :help true)
        (throw (ex-info "unknown conformance option"
                        {:kind :invalid-command :option (first remaining)}))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println conformance/usage) (System/exit 0))
        (let [report (run-suite! options)]
          (println (pr-str (select-keys report [:schema :ok :sections])))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
