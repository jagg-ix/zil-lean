(ns zil.port.verify
  "Verify generated Lean modules and their aggregate import."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.port.library :as library])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files Path Paths StandardCopyOption)))

(def default-manifest "generated/zil/manifest.edn")
(def default-output "generated/zil/verification.edn")
(def default-aggregate "generated/zil/All.lean")
(def default-command ["lake" "env" "lean"])

(defn- absolute-path ^Path [value]
  (.normalize (.toAbsolutePath (Paths/get (str value) (make-array String 0)))))

(defn- path-string [^Path path]
  (str/replace (.toString path) "\\" "/"))

(defn- atomic-write! [path text]
  (let [target (absolute-path path)
        parent (.getParent target)
        _ (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0))
        temporary (Files/createTempFile parent ".zil-verify-" ".tmp"
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

(defn run-command
  [{:keys [command environment directory]}]
  (let [builder (ProcessBuilder. ^java.util.List (vec command))
        _ (when directory (.directory builder (io/file directory)))
        env (.environment builder)
        _ (doseq [[key value] environment] (.put env (name key) (str value)))
        process (.start builder)
        out-future (future (slurp (.getInputStream process)))
        err-future (future (slurp (.getErrorStream process)))
        exit (.waitFor process)]
    {:exit exit :out @out-future :err @err-future :command (vec command)}))

(defn read-manifest! [path]
  (let [file (io/file path)]
    (when-not (.exists file)
      (throw (ex-info "Library manifest does not exist" {:path path})))
    (let [manifest (edn/read-string (slurp file))]
      (when-not (= "ZIL-LIBRARY-MANIFEST/1" (:schema manifest))
        (throw (ex-info "Unsupported library manifest" {:schema (:schema manifest)})))
      manifest)))

(defn aggregate-source [entries]
  (let [namespaces (->> entries
                        (filter #(contains? #{:compiled :checked} (:status %)))
                        (map :namespace)
                        distinct
                        sort)]
    (str (str/join "\n" (map #(str "import " %) namespaces))
         (when (seq namespaces) "\n"))))

(defn- base-entry [entry]
  (select-keys entry [:source :root :relative :output :namespace
                      :source-sha256 :output-sha256]))

(defn- verify-entry
  [{:keys [runner command directory]
    :or {runner run-command command default-command}}
   entry]
  (let [output (:output entry)
        file (io/file output)]
    (cond
      (not (contains? #{:compiled :checked} (:status entry)))
      (assoc (base-entry entry) :status :skipped :reason :source-not-compiled)

      (not (.exists file))
      (assoc (base-entry entry) :status :missing)

      (not= (:output-sha256 entry) (library/file-sha256 file))
      (assoc (base-entry entry) :status :hash-mismatch
             :actual-output-sha256 (library/file-sha256 file))

      :else
      (let [invocation (into (vec command) [(.getCanonicalPath file)])
            result (runner {:command invocation :directory directory :environment {}})]
        (if (zero? (:exit result))
          (assoc (base-entry entry) :status :verified)
          (assoc (base-entry entry)
                 :status :failed
                 :exit (:exit result)
                 :error (str/trim (or (:err result) ""))
                 :command (:command result invocation)))))))

(defn- aggregate-environment [output-root]
  (let [existing (System/getenv "LEAN_PATH")
        separator (System/getProperty "path.separator")]
    {"LEAN_PATH" (if (str/blank? existing)
                   (str output-root)
                   (str output-root separator existing))}))

(defn verify-manifest!
  [{:keys [manifest output aggregate runner command directory write-aggregate]
    :or {manifest default-manifest
         output default-output
         aggregate default-aggregate
         runner run-command
         command default-command
         write-aggregate true}}]
  (let [manifest-data (read-manifest! manifest)
        entries (mapv #(verify-entry {:runner runner :command command :directory directory} %)
                      (:entries manifest-data))
        aggregate-text (aggregate-source (:entries manifest-data))
        aggregate-path (path-string (absolute-path aggregate))
        _ (when write-aggregate (atomic-write! aggregate-path aggregate-text))
        output-root (:output-root manifest-data)
        aggregate-result
        (if (or (not write-aggregate) (str/blank? aggregate-text))
          {:path aggregate-path :status :skipped}
          (let [invocation (into (vec command) [aggregate-path])
                result (runner {:command invocation
                                :directory directory
                                :environment (aggregate-environment output-root)})]
            (if (zero? (:exit result))
              {:path aggregate-path
               :status :verified
               :sha256 (library/text-sha256 aggregate-text)
               :imports (count (filter #(str/starts-with? % "import ")
                                       (str/split-lines aggregate-text)))}
              {:path aggregate-path
               :status :failed
               :exit (:exit result)
               :error (str/trim (or (:err result) ""))
               :command (:command result invocation)})))
        ok (and (every? #(= :verified (:status %)) entries)
                (contains? #{:verified :skipped} (:status aggregate-result)))
        report (sorted-map
                :schema "ZIL-LEAN-VERIFY/1"
                :manifest (path-string (absolute-path manifest))
                :output-root output-root
                :ok ok
                :verified (count (filter #(= :verified (:status %)) entries))
                :failed (count (remove #(= :verified (:status %)) entries))
                :entries entries
                :aggregate aggregate-result)]
    (atomic-write! output (str (pr-str report) "\n"))
    report))

(def usage
  "zil-verify-generated [--manifest FILE] [--output FILE] [--aggregate FILE] [--no-aggregate]")

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:manifest default-manifest
                  :output default-output
                  :aggregate default-aggregate
                  :write-aggregate true}]
    (if-not remaining
      options
      (case (first remaining)
        "--manifest" (recur (nnext remaining) (assoc options :manifest (second remaining)))
        "--output" (recur (nnext remaining) (assoc options :output (second remaining)))
        "--aggregate" (recur (nnext remaining) (assoc options :aggregate (second remaining)))
        "--no-aggregate" (recur (next remaining) (assoc options :write-aggregate false))
        "--help" (assoc options :help true)
        (throw (ex-info "Unknown verifier argument" {:argument (first remaining)}))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (verify-manifest! options)]
          (println (if (:ok report) "generated Lean verification passed"
                     "generated Lean verification failed"))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
