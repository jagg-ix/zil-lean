(ns zil.port.embedded-native
  "Compile explicitly delimited ZIL blocks from host-language source files."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.embedded :as embedded]
            [zil.port.library :as library]
            [zil.preprocess :as preprocess])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files Path Paths StandardCopyOption)))

(def default-roots ["."])
(def default-output "generated/embedded")
(def default-manifest "generated/embedded/manifest.edn")
(def default-namespace "Zil.Embedded")
(def default-command ["lake" "exe" "zil" "--" "compile"])
(def default-verify-command ["lake" "env" "lean"])
(def supported-extensions #{"lean" "py" "clj" "cljs" "cljc" "rs" "md"})

(defn- absolute-path ^Path [value]
  (.normalize (.toAbsolutePath (Paths/get (str value) (make-array String 0)))))

(defn- path-string [^Path path]
  (str/replace (.toString path) "\\" "/"))

(defn- extension [path]
  (some-> (re-find #"\.([^.]+)$" (str path)) second str/lower-case))

(defn host-files [roots]
  (->> roots
       (map absolute-path)
       (mapcat (fn [^Path root]
                 (cond
                   (Files/isRegularFile root (make-array java.nio.file.LinkOption 0))
                   [root]

                   (Files/isDirectory root (make-array java.nio.file.LinkOption 0))
                   (with-open [stream (Files/walk root (make-array java.nio.file.FileVisitOption 0))]
                     (->> (.iterator stream)
                          iterator-seq
                          (filter #(Files/isRegularFile ^Path % (make-array java.nio.file.LinkOption 0)))
                          (filter #(contains? supported-extensions (extension %)))
                          (map #(.normalize (.toAbsolutePath ^Path %)))
                          doall))

                   :else
                   (throw (ex-info "Embedded source root does not exist"
                                   {:root (path-string root)})))))
       distinct
       (sort-by path-string)
       vec))

(defn- owning-root [roots ^Path source]
  (->> roots
       (map absolute-path)
       (filter #(or (= source %) (.startsWith source ^Path %)))
       (sort-by #(- (.getNameCount ^Path %)))
       first))

(defn- relative-source [^Path root ^Path source]
  (if (= root source)
    (.getFileName source)
    (.relativize root source)))

(defn- stable-scan-path [^Path root ^Path source]
  (str (library/root-label root) "/" (path-string (relative-source root source))))

(defn- macro-text-for [source lib-dir]
  (if (str/blank? (or lib-dir ""))
    ""
    (->> (preprocess/collect-lib-zc-files (str source) lib-dir)
         (map slurp)
         (str/join "\n"))))

(defn- scan-host [roots lib-dir ^Path source]
  (let [root (or (owning-root roots source)
                 (throw (ex-info "Host source is outside configured roots"
                                 {:source (path-string source)})))
        relative (relative-source root source)
        scan-path (stable-scan-path root source)
        report (embedded/scan-text scan-path
                                   (slurp (.toFile source))
                                   {:macro-text (macro-text-for source lib-dir)
                                    :project (library/root-label root)})]
    {:host (path-string source)
     :root (path-string root)
     :relative (path-string relative)
     :scan-path scan-path
     :language (name (:language report))
     :source-hash (:source_hash report)
     :blocks (:blocks report)}))

(defn scan-hosts
  [{:keys [roots lib-dir] :or {roots default-roots}}]
  (reduce
   (fn [state source]
     (try
       (let [report (scan-host roots lib-dir source)]
         (-> state
             (update :hosts conj (dissoc report :blocks))
             (update :blocks into
                     (map-indexed (fn [ordinal block]
                                    (assoc block
                                           :ordinal ordinal
                                           :host (:host report)
                                           :root (:root report)
                                           :relative (:relative report)
                                           :scan-path (:scan-path report)
                                           :language (:language report)))
                                  (:blocks report)))))
       (catch Exception error
         (update state :errors conj
                 {:host (path-string source)
                  :message (.getMessage error)
                  :data (ex-data error)}))))
   {:hosts [] :blocks [] :errors []}
   (host-files roots)))

(defn- path-segments [relative]
  (let [path (Paths/get (str relative) (make-array String 0))
        parent (.getParent path)]
    (if parent
      (mapv #(.toString %) (iterator-seq (.iterator parent)))
      [])))

(defn- stem [relative]
  (-> (Paths/get (str relative) (make-array String 0))
      .getFileName
      str
      (str/replace #"\.[^.]+$" "")))

(defn- block-module [block]
  (str "embedded.block." (str/replace (:block_id block) #"[^A-Za-z0-9]+" "_")))

(defn block-source [block]
  (str "MODULE " (block-module block) ".\n\n"
       (str/join "\n" (:statements block))
       "\n"))

(defn plan-block
  [{:keys [output-root namespace-prefix]
    :or {output-root default-output namespace-prefix default-namespace}}
   block]
  (let [root-label (library/namespace-segment
                    (.getName (io/file (:root block))))
        segments (map library/namespace-segment (path-segments (:relative block)))
        file-segment (library/namespace-segment (stem (:relative block)))
        block-segment (str "Block" (:ordinal block))
        namespace (str/join "." (concat (str/split namespace-prefix #"\.")
                                        [root-label]
                                        segments
                                        [file-segment block-segment]))
        output-relative (reduce (fn [^Path current segment]
                                  (.resolve current segment))
                                (Paths/get root-label (make-array String 0))
                                (concat segments [file-segment]))
        output (.resolve (absolute-path output-root)
                         (.resolve output-relative (str block-segment ".lean")))
        source-text (block-source block)]
    (-> (select-keys block [:block_id :target :trust :start_line :end_line
                            :source_hash :macro_revision :module :namespace
                            :project :source_span :declaration_kind :ordinal
                            :host :root :relative :scan-path :language])
        (assoc :output (path-string output)
               :lean-namespace namespace
               :zc-sha256 (library/text-sha256 source-text)
               :zc-bytes (count (.getBytes source-text StandardCharsets/UTF_8))
               :source-text source-text))))

(defn validate-plan! [entries]
  (doseq [[field values] [[:output (map :output entries)]
                          [:lean-namespace (map :lean-namespace entries)]
                          [:block_id (map :block_id entries)]]]
    (when-not (= (count values) (count (distinct values)))
      (throw (ex-info "Embedded compilation plan contains collisions"
                      {:field field :values values}))))
  entries)

(defn plan
  [{:keys [roots output-root namespace-prefix lib-dir]
    :or {roots default-roots
         output-root default-output
         namespace-prefix default-namespace}
    :as options}]
  (let [scan (scan-hosts {:roots roots :lib-dir lib-dir})
        entries (->> (:blocks scan)
                     (mapv #(plan-block options %))
                     (sort-by (juxt :host :ordinal))
                     validate-plan!)]
    {:hosts (:hosts scan)
     :scan-errors (:errors scan)
     :entries entries}))

(defn run-command
  [{:keys [command environment directory]}]
  (let [builder (ProcessBuilder. ^java.util.List (vec command))
        _ (when directory (.directory builder (io/file directory)))
        env (.environment builder)
        _ (doseq [[key value] environment] (.put env (str key) (str value)))
        process (.start builder)
        out-future (future (slurp (.getInputStream process)))
        err-future (future (slurp (.getErrorStream process)))
        exit (.waitFor process)]
    {:exit exit :out @out-future :err @err-future :command (vec command)}))

(defn- atomic-write! [path text]
  (let [target (absolute-path path)
        parent (.getParent target)
        _ (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0))
        temporary (Files/createTempFile parent ".zil-embedded-" ".tmp"
                                        (make-array java.nio.file.attribute.FileAttribute 0))]
    (Files/writeString temporary (str text) StandardCharsets/UTF_8
                       (into-array java.nio.file.OpenOption []))
    (try
      (Files/move temporary target
                  (into-array StandardCopyOption
                              [StandardCopyOption/ATOMIC_MOVE
                               StandardCopyOption/REPLACE_EXISTING]))
      (catch java.nio.file.AtomicMoveNotSupportedException _
        (Files/move temporary target
                    (into-array StandardCopyOption
                                [StandardCopyOption/REPLACE_EXISTING]))))
    target))

(defn- lean-path-environment [output-root]
  (let [root (path-string (absolute-path output-root))
        existing (System/getenv "LEAN_PATH")
        separator (System/getProperty "path.separator")]
    {"LEAN_PATH" (if (str/blank? existing)
                   root
                   (str root separator existing))}))

(defn- compile-entry
  [{:keys [runner command verify-command check-only temp-root output-root
           verify-generated directory]
    :or {runner run-command
         command default-command
         verify-command default-verify-command
         verify-generated true}}
   entry]
  (let [temporary-root (absolute-path (or temp-root (System/getProperty "java.io.tmpdir")))
        _ (Files/createDirectories temporary-root
                                   (make-array java.nio.file.attribute.FileAttribute 0))
        temporary (Files/createTempFile temporary-root "zil-embedded-" ".zc"
                                        (make-array java.nio.file.attribute.FileAttribute 0))]
    (try
      (Files/writeString temporary (:source-text entry) StandardCharsets/UTF_8
                         (into-array java.nio.file.OpenOption []))
      (let [compile-invocation (into (vec command)
                                     [(path-string temporary) "-" (:lean-namespace entry)])
            compiled (runner {:command compile-invocation
                              :directory directory
                              :environment {}})]
        (if-not (zero? (:exit compiled))
          (-> entry
              (dissoc :source-text)
              (assoc :status :failed
                     :phase :compile
                     :exit (:exit compiled)
                     :error (str/trim (or (:err compiled) ""))
                     :command (:command compiled compile-invocation)))
          (let [output-sha (library/text-sha256 (:out compiled))
                bytes (count (.getBytes (str (:out compiled)) StandardCharsets/UTF_8))]
            (cond
              check-only
              (-> entry
                  (dissoc :source-text)
                  (assoc :status :checked
                         :output-sha256 output-sha
                         :bytes bytes))

              :else
              (do
                (atomic-write! (:output entry) (:out compiled))
                (if-not verify-generated
                  (-> entry
                      (dissoc :source-text)
                      (assoc :status :compiled
                             :output-sha256 output-sha
                             :bytes bytes))
                  (let [verify-invocation (into (vec verify-command) [(:output entry)])
                        verified (runner {:command verify-invocation
                                          :directory directory
                                          :environment (lean-path-environment output-root)})]
                    (if (zero? (:exit verified))
                      (-> entry
                          (dissoc :source-text)
                          (assoc :status :verified
                                 :output-sha256 output-sha
                                 :bytes bytes))
                      (-> entry
                          (dissoc :source-text)
                          (assoc :status :verification-failed
                                 :phase :verify
                                 :output-sha256 output-sha
                                 :bytes bytes
                                 :exit (:exit verified)
                                 :error (str/trim (or (:err verified) ""))
                                 :command (:command verified verify-invocation)))))))))))
      (finally
        (Files/deleteIfExists temporary)))))

(defn- write-edn! [path data]
  (atomic-write! path (str (pr-str data) "\n")))

(defn compile-embedded!
  [{:keys [roots output-root manifest namespace-prefix check-only require-blocks
           verify-generated]
    :or {roots default-roots
         output-root default-output
         manifest default-manifest
         namespace-prefix default-namespace
         verify-generated true}
    :as options}]
  (let [{:keys [hosts scan-errors entries]} (plan options)
        compile-options (assoc options
                               :output-root output-root
                               :verify-generated verify-generated)
        results (mapv #(compile-entry compile-options %) entries)
        no-block-failure (and require-blocks (empty? results))
        accepted-statuses (if verify-generated
                            #{:verified :checked}
                            #{:compiled :checked})
        ok (and (empty? scan-errors)
                (not no-block-failure)
                (every? #(contains? accepted-statuses (:status %)) results))
        report (sorted-map
                :schema "ZIL-EMBEDDED-MANIFEST/1"
                :roots (mapv #(path-string (absolute-path %)) roots)
                :output-root (path-string (absolute-path output-root))
                :namespace-prefix namespace-prefix
                :check-only (boolean check-only)
                :verify-generated (boolean verify-generated)
                :require-blocks (boolean require-blocks)
                :ok ok
                :host-count (count hosts)
                :block-count (count results)
                :verified (count (filter #(= :verified (:status %)) results))
                :compiled (count (filter #(= :compiled (:status %)) results))
                :checked (count (filter #(= :checked (:status %)) results))
                :failed (count (remove #(contains? accepted-statuses (:status %)) results))
                :hosts hosts
                :scan-errors scan-errors
                :entries results
                :failures (cond-> []
                            no-block-failure
                            (conj {:kind :no-embedded-blocks})))]
    (write-edn! manifest report)
    report))

(def usage
  (str "zil-embedded-native [--root PATH]... [--out DIR] [--manifest FILE] "
       "[--namespace NAME] [--lib DIR] [--check] [--no-verify] [--require-blocks]"))

(defn- value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "Missing embedded compiler option value" {:option flag}))))

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:roots []
                  :output-root default-output
                  :manifest default-manifest
                  :namespace-prefix default-namespace
                  :verify-generated true}]
    (if-not remaining
      (update options :roots #(if (seq %) % default-roots))
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
        (throw (ex-info "Unknown embedded compiler argument"
                        {:argument (first remaining)}))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (compile-embedded! options)]
          (println (if (:ok report) "embedded ZIL compilation passed"
                     "embedded ZIL compilation failed"))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
