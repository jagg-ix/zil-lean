(ns zil.port.retirement
  "Guard native-first entry points and classify remaining legacy consumers."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def default-gate "generated/zil/port-gate.edn")
(def default-verification "generated/zil/verification.edn")
(def default-embedded "generated/embedded/manifest.edn")
(def default-policy "legacy-retirement.edn")
(def default-output "generated/zil/retirement.edn")
(def text-extensions
  #{"clj" "cljc" "cljs" "edn" "sh" "bash" "md" "txt" "lean" "py" "rs" "zc"})

(defn- canonical-file [value]
  (.getCanonicalFile (io/file value)))

(defn- relative-path [root file]
  (-> (.toPath (canonical-file root))
      (.relativize (.toPath (canonical-file file)))
      str
      (str/replace "\\" "/")))

(defn- extension [file]
  (some-> (re-find #"\.([^.]+)$" (.getName (io/file file))) second str/lower-case))

(defn- text-file? [file]
  (let [name (.getName (io/file file))]
    (or (contains? text-extensions (extension file))
        (contains? #{"deps.edn" "build.clj" "Makefile"} name)
        (not (str/includes? name ".")))))

(defn source-files [repository-root roots]
  (->> roots
       (map #(io/file repository-root %))
       (mapcat (fn [root]
                 (cond
                   (.isFile root) [root]
                   (.isDirectory root) (filter #(.isFile %) (file-seq root))
                   :else
                   (throw (ex-info "Retirement scan root does not exist"
                                   {:root (.getPath root)})))))
       (filter text-file?)
       (map canonical-file)
       distinct
       (sort-by #(.getPath %))
       vec))

(defn- read-edn! [path schema]
  (let [file (io/file path)]
    (when-not (.exists file)
      (throw (ex-info "Retirement evidence file does not exist" {:path path})))
    (let [data (edn/read-string (slurp file))]
      (when-not (= schema (:schema data))
        (throw (ex-info "Unsupported retirement evidence schema"
                        {:path path :expected schema :actual (:schema data)})))
      data)))

(defn- read-policy! [path]
  (let [file (io/file path)]
    (when-not (.exists file)
      (throw (ex-info "Retirement policy does not exist" {:path path})))
    (let [policy (edn/read-string (slurp file))]
      (when-not (seq (:components policy))
        (throw (ex-info "Retirement policy requires at least one component"
                        {:path path})))
      (doseq [[component config] (:components policy)]
        (when-not (seq (:patterns config))
          (throw (ex-info "Retirement component requires at least one consumer pattern"
                          {:component component}))))
      policy)))

(defn- path-matches? [path exact prefixes]
  (or (contains? (set exact) path)
      (some #(str/starts-with? path %) prefixes)))

(defn- match-lines [text pattern]
  (let [compiled (re-pattern pattern)]
    (->> (str/split-lines text)
         (map-indexed vector)
         (keep (fn [[index line]]
                 (when (re-find compiled line)
                   {:line (inc index) :text (str/trim line)})))
         vec)))

(defn- component-consumers
  [repository-root files non-blocking-prefixes component config]
  (let [allow-paths (:allow-paths config [])
        allow-prefixes (:allow-prefixes config [])]
    (->> files
         (mapcat (fn [file]
                   (let [path (relative-path repository-root file)
                         text (try (slurp file) (catch Exception _ ""))]
                     (mapcat
                      (fn [{:keys [id pattern]}]
                        (map (fn [match]
                               (let [allowed (path-matches? path allow-paths allow-prefixes)
                                     non-blocking (some #(str/starts-with? path %)
                                                        non-blocking-prefixes)]
                                 (sorted-map
                                  :component component
                                  :pattern id
                                  :path path
                                  :line (:line match)
                                  :text (:text match)
                                  :allowed allowed
                                  :non-blocking non-blocking
                                  :blocking (and (not allowed) (not non-blocking)))))
                             (match-lines text pattern)))
                      (:patterns config [])))))
         (sort-by (juxt :path :line :pattern))
         vec)))

(defn- gate-component-ready? [gate component]
  (true? (get-in gate [:components component :retirable])))

(defn- evidence-failures [gate verification embedded config]
  (cond-> []
    (and (:require-gate-ok config) (not (:ok gate)))
    (conj {:kind :gate-failed})

    (some #(not (gate-component-ready? gate %)) (:gate-components config []))
    (conj {:kind :gate-components-not-retirable
           :components (vec (remove #(gate-component-ready? gate %)
                                    (:gate-components config [])))})

    (and (:require-verification config) (not (:ok verification)))
    (conj {:kind :generated-verification-failed})

    (and (:require-aggregate config)
         (not= :verified (get-in verification [:aggregate :status])))
    (conj {:kind :aggregate-not-verified
           :status (get-in verification [:aggregate :status])})

    (and (:require-embedded config) (not (:ok embedded)))
    (conj {:kind :embedded-compilation-failed})

    (< (:block-count embedded 0) (:min-embedded-blocks config 0))
    (conj {:kind :embedded-block-coverage
           :actual (:block-count embedded 0)
           :required (:min-embedded-blocks config)})))

(defn evaluate-component
  [repository-root files non-blocking-prefixes gate verification embedded
   [component config]]
  (let [consumers (component-consumers repository-root files non-blocking-prefixes
                                       component config)
        blockers (filterv :blocking consumers)
        evidence (evidence-failures gate verification embedded config)
        state (cond
                (seq evidence) :active
                (seq blockers) :frozen
                :else :ready-to-remove)]
    [component
     (sorted-map
      :state state
      :evidence-ok (empty? evidence)
      :evidence-failures evidence
      :consumer-count (count consumers)
      :blocking-consumer-count (count blockers)
      :consumers consumers)]))

(defn evaluate
  [gate verification embedded policy]
  (let [repository-root (canonical-file (:repository-root policy "."))
        scan-roots (:scan-roots policy ["bin" "src" "deps.edn" "build.clj"])
        files (source-files repository-root scan-roots)
        non-blocking-prefixes (:non-blocking-prefixes policy ["test/" "docs/" "examples/"])
        components (->> (:components policy)
                        (map #(evaluate-component repository-root files non-blocking-prefixes
                                                  gate verification embedded %))
                        (into (sorted-map)))
        blockers (->> components
                      (keep (fn [[component result]]
                              (when (= :frozen (:state result))
                                {:kind :legacy-consumers-remain
                                 :component component
                                 :consumers (filterv :blocking (:consumers result))})))
                      vec)
        ready (->> components
                   (keep (fn [[component result]]
                           (when (= :ready-to-remove (:state result)) component)))
                   sort
                   vec)
        active (->> components
                    (keep (fn [[component result]]
                            (when (= :active (:state result)) component)))
                    sort
                    vec)]
    (sorted-map
     :schema "ZIL-RETIREMENT/1"
     :ok (empty? blockers)
     :repository-root (.getPath repository-root)
     :scanned-files (count files)
     :ready-to-remove ready
     :active active
     :components components
     :failures blockers)))

(defn- deep-merge [left right]
  (merge-with (fn [a b]
                (if (and (map? a) (map? b))
                  (deep-merge a b)
                  b))
              left right))

(def default-policy-data
  {:repository-root "."
   :scan-roots ["bin" "src" "test" "docs" "examples" "deps.edn" "build.clj"]
   :non-blocking-prefixes ["test/" "docs/" "examples/"]
   :components {}})

(defn run-guard!
  [{:keys [gate verification embedded policy output require-ready]
    :or {gate default-gate
         verification default-verification
         embedded default-embedded
         policy default-policy
         output default-output}}]
  (let [gate-data (read-edn! gate "ZIL-PORT-GATE/1")
        verification-data (read-edn! verification "ZIL-LEAN-VERIFY/1")
        embedded-data (read-edn! embedded "ZIL-EMBEDDED-MANIFEST/1")
        policy-data (deep-merge default-policy-data (read-policy! policy))
        report (evaluate gate-data verification-data embedded-data policy-data)
        report (if require-ready
                 (let [not-ready (->> (:components report)
                                      (remove (fn [[_ result]]
                                                (= :ready-to-remove (:state result))))
                                      (mapv first))]
                   (if (empty? not-ready)
                     report
                     (-> report
                         (assoc :ok false)
                         (update :failures into
                                 (mapv (fn [component]
                                         {:kind :component-not-ready
                                          :component component})
                                       not-ready)))))
                 report)]
    (when-let [parent (.getParentFile (io/file output))] (.mkdirs parent))
    (spit output (str (pr-str report) "\n"))
    report))

(def usage
  (str "zil-retirement [--gate FILE] [--verification FILE] [--embedded FILE] "
       "[--policy FILE] [--output FILE] [--require-ready]"))

(defn- value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "Missing retirement option value" {:option flag}))))

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:gate default-gate
                  :verification default-verification
                  :embedded default-embedded
                  :policy default-policy
                  :output default-output}]
    (if-not remaining
      options
      (case (first remaining)
        "--gate" (recur (nnext remaining) (assoc options :gate (value! remaining "--gate")))
        "--verification" (recur (nnext remaining)
                                (assoc options :verification (value! remaining "--verification")))
        "--embedded" (recur (nnext remaining)
                            (assoc options :embedded (value! remaining "--embedded")))
        "--policy" (recur (nnext remaining)
                          (assoc options :policy (value! remaining "--policy")))
        "--output" (recur (nnext remaining)
                          (assoc options :output (value! remaining "--output")))
        "--require-ready" (recur (next remaining) (assoc options :require-ready true))
        "--help" (assoc options :help true)
        (throw (ex-info "Unknown retirement argument" {:argument (first remaining)}))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (run-guard! options)]
          (println (if (:ok report) "legacy retirement guard passed"
                     "legacy retirement guard failed"))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
