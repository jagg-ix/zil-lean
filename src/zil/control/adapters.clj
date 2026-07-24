(ns zil.control.adapters
  "Control-plane adapters for existing macro, library, and embedded orchestration."
  (:gen-class)
  (:require [clojure.string :as str]
            [zil.control.command :as command]
            [zil.control.runtime :as runtime]
            [zil.port.embedded-native :as embedded]
            [zil.port.library :as library]
            [zil.port.native-macro :as native-macro]))

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
    (response-result
     command
     (command/execute! control-plane
                       (second command)
                       (:input-path (operation-request command))
                       (:arguments (operation-request command))))))

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
        (throw (ex-info "unknown embedded option"
                        {:kind :invalid-command :option (first remaining)}))))))

(def usage
  (str "zil-control-adapters macro <compile|expand|parity> <model.zc> [options]\n"
       "zil-control-adapters library [options]\n"
       "zil-control-adapters embedded [options]"))

(defn -main [& args]
  (try
    (let [[surface & tail] args
          result
          (case surface
            "macro" (let [options (parse-macro tail)]
                      (case (:mode options)
                        "compile" (compile-macro! options)
                        "expand" (expand-macro! options)
                        "parity" (parity-macro! options)))
            "library" (compile-library! (parse-library tail))
            "embedded" (compile-embedded! (parse-embedded tail))
            (throw (ex-info usage {:kind :invalid-command :surface surface})))]
      (when (map? result)
        (println (pr-str (select-keys result
                                     [:schema :ok :mode :model :output :check-only
                                      :output-root :block-count :file-count]))))
      (System/exit (if (false? (:ok result)) 1 0)))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
