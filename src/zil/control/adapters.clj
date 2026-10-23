(ns zil.control.adapters
  "Control-plane adapters for existing macro, library, and embedded orchestration."
  (:gen-class)
  (:require [clojure.string :as str]
            [zil.control.command :as command]
            [zil.control.runtime :as runtime]
            [zil.port.embedded-native :as embedded]
            [zil.port.library :as library]
            [zil.port.native-macro :as native-macro]))

(declare adapter-command request-runner)

(defn- matrix-entries [path]
  (->> (str/split-lines (slurp path))
       (remove #(or (str/blank? %) (str/starts-with? (str/trim %) "#")))
       (mapv (fn [line]
               (let [fields (str/split line #"\t" -1)]
                 (when-not (= 3 (count fields))
                   (throw (ex-info "macro matrix row must have three tab-separated fields"
                                   {:kind :invalid-matrix-row :line line})))
                 (let [[name lib model] fields]
                   (when (some str/blank? fields)
                     (throw (ex-info "macro matrix fields must be nonempty"
                                     {:kind :invalid-matrix-row :line line})))
                   {:name name :lib lib :model model}))))))

(defn qualify-matrix! [{:keys [matrix output]}]
  (let [root (java.io.File. (System/getProperty "user.dir"))
        output-root (java.io.File. output)
        _ (.mkdirs output-root)
        entries (matrix-entries matrix)]
    (runtime/with-control-plane
     {:pool-size 1}
     (fn [control-plane]
       (let [results
             (mapv
              (fn [{:keys [name lib model]}]
                (try
                  (let [lib-dir
                        (if (str/starts-with? lib "@")
                          (let [source (java.io.File. root (subs lib 1))
                                isolated (java.io.File. output-root (str "." name "-lib"))]
                            (.mkdirs isolated)
                            (when-not (.isFile source)
                              (throw (ex-info "macro source file does not exist"
                                              {:kind :missing-macro-library :path (.getPath source)})))
                            (java.nio.file.Files/copy
                             (.toPath source)
                             (.toPath (java.io.File. isolated (.getName source)))
                             (into-array java.nio.file.CopyOption
                                         [java.nio.file.StandardCopyOption/REPLACE_EXISTING]))
                            isolated)
                          (java.io.File. root lib))
                        model-file (java.io.File. root model)
                        report-file (java.io.File. output-root (str name ".parity.edn"))
                        lean-file (java.io.File. output-root (str name ".lean"))
                        runner (request-runner control-plane)
                        options {:model (.getPath model-file)
                                 :lib-dir (.getPath lib-dir)
                                 :native-command [adapter-command]
                                 :runner runner}
                        report (native-macro/parity-report options)]
                    (spit report-file (str (pr-str report) "\n"))
                    (if-not (:ok report)
                      {:name name :ok false :stage "parity" :report (.getPath report-file)}
                      (do
                        (native-macro/compile-model!
                         (assoc options :output (.getPath lean-file)))
                        {:name name :ok true
                         :report (.getPath report-file)
                         :lean (.getPath lean-file)})))
                  (catch Exception error
                    {:name name :ok false :stage "compile"
                     :error (.getMessage error)
                     :detail (:error (ex-data error))})))
              entries)
             passed (count (filter :ok results))
             failed (- (count results) passed)]
         (doseq [{:keys [name ok stage error]} results]
           (println (if ok "[pass]" "[fail]") name
                    (when stage (str " " stage))
                    (when error (str ": " error))))
         (doseq [{:keys [name detail]} results :when detail]
           (println "[detail]" name detail))
         (println (pr-str {:schema "ZIL-MACRO-MATRIX/1"
                           :passed passed :failed failed
                           :results results}))
         (System/exit (if (zero? failed) 0 1)))))))

(defn- parse-matrix [args]
  (loop [remaining (seq args) options {}]
    (if-not remaining
      (do
        (when-not (and (:matrix options) (:output options))
          (throw (ex-info "macro matrix requires --matrix FILE and --out DIR"
                          {:kind :invalid-command})))
        options)
      (case (first remaining)
        "--matrix" (let [value (second remaining)]
                     (when-not value
                       (throw (ex-info "missing --matrix value" {:kind :invalid-command})))
                     (recur (nnext remaining) (assoc options :matrix value)))
        "--out" (let [value (second remaining)]
                  (when-not value
                    (throw (ex-info "missing --out value" {:kind :invalid-command})))
                  (recur (nnext remaining) (assoc options :output value)))
        (throw (ex-info "unknown macro matrix option"
                        {:kind :invalid-command :option (first remaining)}))))))

(def adapter-command "zil-control-adapter")

(defn- semantic-command? [command]
  (= adapter-command (first command)))

(defn- operation-request [command]
  (let [[_ operation input-path _ & tail] command
        arguments (case operation
                    "compile" [(or (first tail) "-")]
                    "expand" []
                    "conformance" []
                    tail)]
    {:operation operation
     :input-path input-path
     :arguments arguments}))

(defn- response-result [command response]
  (if (= "ok" (:status response))
    {:exit 0
     :out (:payload response)
     :err ""
     :command (vec command)
     :exchange response}
    {:exit 1
     :out ""
     :err (str/join "\n" (:errors response))
     :command (vec command)
     :exchange response}))

(defn request-runner
  "Runner compatible with `zil.port.native-macro/invoke-native`."
  [control-plane]
  (fn [{:keys [command]}]
    (when-not (semantic-command? command)
      (throw (ex-info "control-plane request runner received a nonsemantic command"
                      {:kind :adapter-error :command command})))
    (let [{:keys [operation input-path arguments]} (operation-request command)]
      (response-result
       command
       (command/execute! control-plane operation input-path arguments)))))

(defn vector-runner
  "Runner compatible with `zil.port.library/run-command`."
  [control-plane]
  (fn [command]
    ((request-runner control-plane) {:command (vec command)})))

(defn embedded-runner
  "Route embedded compilation through exchange and keep generated Lean verification external."
  [control-plane]
  (fn [{:keys [command] :as request}]
    (if (semantic-command? command)
      ((request-runner control-plane) request)
      (embedded/run-command request))))

(defn compile-macro! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (native-macro/compile-model!
      (assoc options
             :native-command [adapter-command]
             :runner (request-runner control-plane))))))

(defn expand-macro! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (native-macro/expand-model!
      (assoc options
             :native-command [adapter-command]
             :runner (request-runner control-plane))))))

(defn parity-macro! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (native-macro/parity-model!
      (assoc options
             :native-command [adapter-command]
             :runner (request-runner control-plane))))))

(defn compile-library! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (library/compile-tree!
      (assoc options
             :command [adapter-command "compile"]
             :runner (vector-runner control-plane))))))

(defn compile-embedded! [options]
  (runtime/with-control-plane
   options
   (fn [control-plane]
     (embedded/compile-embedded!
      (assoc options
             :command [adapter-command "compile"]
             :runner (embedded-runner control-plane))))))

(defn- value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "missing option value" {:kind :invalid-command :option flag}))))

(defn- parse-macro [args]
  (let [[mode model & tail] args]
    (when-not (contains? #{"compile" "expand" "parity"} mode)
      (throw (ex-info "unknown macro command" {:kind :invalid-command :command mode})))
    (when (str/blank? model)
      (throw (ex-info "macro command requires a model" {:kind :invalid-command})))
    (loop [remaining (seq tail)
           options {:mode mode :model model}]
      (if-not remaining
        options
        (case (first remaining)
          "--output" (recur (nnext remaining)
                            (assoc options :output (value! remaining "--output")))
          "--namespace" (recur (nnext remaining)
                               (assoc options :namespace (value! remaining "--namespace")))
          "--lib" (recur (nnext remaining)
                         (assoc options :lib-dir (value! remaining "--lib")))
          (throw (ex-info "unknown macro option"
                          {:kind :invalid-command :option (first remaining)})))))))

(defn- parse-library [args]
  (loop [remaining (seq args)
         options {:roots []
                  :output-root library/default-output
                  :manifest library/default-manifest
                  :namespace-prefix library/default-namespace}]
    (if-not remaining
      (update options :roots #(if (seq %) % library/default-roots))
      (case (first remaining)
        "--root" (recur (nnext remaining)
                        (update options :roots conj (value! remaining "--root")))
        "--out" (recur (nnext remaining)
                       (assoc options :output-root (value! remaining "--out")))
        "--manifest" (recur (nnext remaining)
                            (assoc options :manifest (value! remaining "--manifest")))
        "--namespace" (recur (nnext remaining)
                             (assoc options :namespace-prefix (value! remaining "--namespace")))
        "--lib" (recur (nnext remaining)
                       (assoc options :lib-dir (value! remaining "--lib")))
        "--check" (recur (next remaining) (assoc options :check-only true))
        "--clean-stale" (recur (next remaining) (assoc options :clean-stale true))
        "--help" (assoc options :help true)
        (throw (ex-info "unknown library option"
                        {:kind :invalid-command :option (first remaining)}))))))

(defn- parse-embedded [args]
  (loop [remaining (seq args)
         options {:roots []
                  :output-root embedded/default-output
                  :manifest embedded/default-manifest
                  :namespace-prefix embedded/default-namespace
                  :verify-generated true}]
    (if-not remaining
      (update options :roots #(if (seq %) % embedded/default-roots))
      (case (first remaining)
        "--root" (recur (nnext remaining)
                        (update options :roots conj (value! remaining "--root")))
        "--out" (recur (nnext remaining)
                       (assoc options :output-root (value! remaining "--out")))
        "--manifest" (recur (nnext remaining)
                            (assoc options :manifest (value! remaining "--manifest")))
        "--namespace" (recur (nnext remaining)
                             (assoc options :namespace-prefix (value! remaining "--namespace")))
        "--lib" (recur (nnext remaining)
                       (assoc options :lib-dir (value! remaining "--lib")))
        "--check" (recur (next remaining) (assoc options :check-only true))
        "--no-verify" (recur (next remaining) (assoc options :verify-generated false))
        "--require-blocks" (recur (next remaining) (assoc options :require-blocks true))
        "--help" (assoc options :help true)
        (throw (ex-info "unknown embedded option"
                        {:kind :invalid-command :option (first remaining)}))))))

(def usage
  (str "zil-control-adapters macro <compile|expand|parity> <model.zc> [options]\n"
       "zil-control-adapters macro-matrix --matrix FILE --out DIR\n"
       "zil-control-adapters library [options]\n"
       "zil-control-adapters embedded [options]"))

(defn -main [& args]
  (try
    (let [[surface & tail] args]
      (when (or (nil? surface) (= surface "--help") (= surface "-h"))
        (println usage)
        (System/exit 0))
      (case surface
        "macro"
        (let [options (parse-macro tail)]
          (case (:mode options)
            "compile" (compile-macro! options)
            "expand" (expand-macro! options)
            "parity" (parity-macro! options)))

        "macro-matrix"
        (qualify-matrix! (parse-matrix tail))

        "library"
        (let [options (parse-library tail)]
          (if (:help options)
            (println library/usage)
            (let [result (compile-library! options)]
              (println (pr-str (select-keys result
                                           [:schema :ok :check-only :output-root])))
              (System/exit (if (:ok result) 0 1)))))

        "embedded"
        (let [options (parse-embedded tail)]
          (if (:help options)
            (println embedded/usage)
            (let [result (compile-embedded! options)]
              (println (if (:ok result)
                         "embedded ZIL compilation passed"
                         "embedded ZIL compilation failed"))
              (System/exit (if (:ok result) 0 1)))))

        (throw (ex-info usage {:kind :invalid-command :surface surface}))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
