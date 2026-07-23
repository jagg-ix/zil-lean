(ns zil.port.library
  "Recursively compile .zc libraries through the native Lean frontend."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files Path Paths StandardCopyOption)
           (java.security MessageDigest)))

(def default-roots ["lib" "libsets" "examples"])
(def default-output "generated/zil")
(def default-manifest "generated/zil/manifest.edn")
(def default-namespace "Zil.Generated")
(def default-command ["lake" "exe" "zil" "--" "compile"])

(defn- absolute-path ^Path [value]
  (.normalize (.toAbsolutePath (Paths/get (str value) (make-array String 0)))))

(defn- path-string [^Path path]
  (-> (.toString path) (str/replace "\\" "/")))

(defn- sha256-bytes [^bytes data]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256") data)]
    (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest))))

(defn file-sha256 [file]
  (sha256-bytes (Files/readAllBytes (.toPath (io/file file)))))

(defn text-sha256 [text]
  (sha256-bytes (.getBytes (str text) StandardCharsets/UTF_8)))

(defn- split-words [value]
  (->> (str/split (str value) #"[^A-Za-z0-9]+")
       (remove str/blank?)))

(defn- upper-first [value]
  (if (str/blank? value)
    ""
    (str (str/upper-case (subs value 0 1)) (subs value 1))))

(defn namespace-segment [value]
  (let [candidate (apply str (map #(upper-first (str/lower-case %))
                                  (split-words value)))
        candidate (if (str/blank? candidate) "Generated" candidate)]
    (if (re-matches #"^[0-9].*" candidate)
      (str "N" candidate)
      candidate)))

(defn file-stem [^Path path]
  (str/replace (.toString (.getFileName path)) #"\.[^.]+$" ""))

(defn root-label [^Path root]
  (namespace-segment (.toString (.getFileName root))))

(defn source-files
  "Return canonical, sorted .zc files under the selected roots."
  [roots]
  (->> roots
       (map absolute-path)
       (mapcat (fn [^Path root]
                 (if (Files/exists root (make-array java.nio.file.LinkOption 0))
                   (with-open [stream (Files/walk root (make-array java.nio.file.FileVisitOption 0))]
                     (->> (.iterator stream)
                          iterator-seq
                          (filter #(Files/isRegularFile ^Path % (make-array java.nio.file.LinkOption 0)))
                          (filter #(str/ends-with? (str/lower-case (.toString ^Path %)) ".zc"))
                          (map #(.normalize (.toAbsolutePath ^Path %)))
                          doall))
                   [])))
       distinct
       (sort-by path-string)
       vec))

(defn- owning-root [roots ^Path source]
  (->> roots
       (map absolute-path)
       (filter #(.startsWith source ^Path %))
       (sort-by #(- (.getNameCount ^Path %)))
       first))

(defn plan-entry
  [{:keys [roots output-root namespace-prefix]} ^Path source]
  (let [root (or (owning-root roots source)
                 (throw (ex-info "Source is outside configured roots"
                                 {:source (path-string source)})))
        relative (.relativize root source)
        parent (.getParent relative)
        path-parts (if parent
                     (map #(.toString %) (iterator-seq (.iterator parent)))
                     [])
        namespace-parts (concat (str/split namespace-prefix #"\.")
                                [(root-label root)]
                                (map namespace-segment path-parts)
                                [(namespace-segment (file-stem source))])
        namespace (str/join "." namespace-parts)
        output-relative (reduce (fn [^Path current segment]
                                  (.resolve current (namespace-segment segment)))
                                (Paths/get (root-label root) (make-array String 0))
                                path-parts)
        output (.resolve (absolute-path output-root)
                         (.resolve output-relative
                                   (str (namespace-segment (file-stem source)) ".lean")))]
    (sorted-map
     :source (path-string source)
     :root (path-string root)
     :relative (path-string relative)
     :output (path-string output)
     :namespace namespace
     :source-sha256 (file-sha256 (.toFile source)))))

(defn validate-plan!
  [entries]
  (let [output-collisions (->> entries (group-by :output)
                               (filter (fn [[_ xs]] (> (count xs) 1)))
                               (into (sorted-map)))
        namespace-collisions (->> entries (group-by :namespace)
                                  (filter (fn [[_ xs]] (> (count xs) 1)))
                                  (into (sorted-map)))]
    (when (or (seq output-collisions) (seq namespace-collisions))
      (throw (ex-info "Library compilation plan contains collisions"
                      {:output-collisions output-collisions
                       :namespace-collisions namespace-collisions})))
    entries))

(defn plan
  [{:keys [roots output-root namespace-prefix]
    :or {roots default-roots
         output-root default-output
         namespace-prefix default-namespace}
    :as options}]
  (let [options (assoc options
                       :roots roots
                       :output-root output-root
                       :namespace-prefix namespace-prefix)]
    (->> (source-files roots)
         (mapv #(plan-entry options %))
         validate-plan!)))

(defn run-command
  "Execute one command and return captured stdout/stderr."
  [command]
  (let [builder (ProcessBuilder. ^java.util.List (vec command))
        process (.start builder)
        out-future (future (slurp (.getInputStream process)))
        err-future (future (slurp (.getErrorStream process)))
        exit (.waitFor process)]
    {:exit exit :out @out-future :err @err-future :command (vec command)}))

(defn- atomic-write! [path text]
  (let [target (absolute-path path)
        parent (.getParent target)
        _ (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0))
        temporary (Files/createTempFile parent ".zil-" ".tmp"
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

(defn- compile-entry
  [{:keys [command runner check-only]
    :or {command default-command runner run-command}}
   entry]
  (let [invocation (into (vec command)
                         [(:source entry) "-" (:namespace entry)])
        {:keys [exit out err] :as result} (runner invocation)]
    (if (zero? exit)
      (let [output-sha (text-sha256 out)
            status (if check-only :checked :compiled)]
        (when-not check-only
          (atomic-write! (:output entry) out))
        (assoc entry
               :status status
               :output-sha256 output-sha
               :bytes (count (.getBytes (str out) StandardCharsets/UTF_8))))
      (assoc entry
             :status :failed
             :exit exit
             :error (str/trim (or err ""))
             :command (:command result invocation)))))

(defn- read-manifest [path]
  (let [file (io/file path)]
    (when (.exists file)
      (edn/read-string (slurp file)))))

(defn- stale-outputs [previous current]
  (let [current-paths (set (map :output (:entries current)))]
    (->> (:entries previous)
         (map :output)
         (remove current-paths)
         sort
         vec)))

(defn- under-root? [root path]
  (.startsWith (absolute-path path) (absolute-path root)))

(defn- delete-stale! [output-root paths]
  (doseq [path paths]
    (when-not (under-root? output-root path)
      (throw (ex-info "Refusing to delete stale output outside output root"
                      {:output-root output-root :path path})))
    (Files/deleteIfExists (absolute-path path))))

(defn compile-tree!
  [{:keys [manifest output-root clean-stale]
    :or {manifest default-manifest output-root default-output}
    :as options}]
  (let [entries (plan options)
        results (mapv #(compile-entry options %) entries)
        report (sorted-map
                :schema "ZIL-LIBRARY-MANIFEST/1"
                :roots (mapv #(path-string (absolute-path %))
                             (or (:roots options) default-roots))
                :output-root (path-string (absolute-path output-root))
                :namespace-prefix (or (:namespace-prefix options) default-namespace)
                :check-only (boolean (:check-only options))
                :ok (every? #(not= :failed (:status %)) results)
                :entries results)
        previous (read-manifest manifest)
        stale (if (and clean-stale previous (:ok report) (not (:check-only report)))
                (stale-outputs previous report)
                [])
        report (assoc report :stale-removed stale)]
    (when (seq stale) (delete-stale! output-root stale))
    (atomic-write! manifest (str (pr-str report) "\n"))
    report))

(defn- parse-cli [args]
  (loop [args (seq args)
         options {:roots []
                  :output-root default-output
                  :manifest default-manifest
                  :namespace-prefix default-namespace}]
    (if-not args
      (update options :roots #(if (seq %) % default-roots))
      (let [[arg value & rest] args]
        (case arg
          "--root" (recur rest (update options :roots conj value))
          "--out" (recur rest (assoc options :output-root value))
          "--manifest" (recur rest (assoc options :manifest value))
          "--namespace" (recur rest (assoc options :namespace-prefix value))
          "--check" (recur (next args) (assoc options :check-only true))
          "--clean-stale" (recur (next args) (assoc options :clean-stale true))
          "--help" (assoc options :help true)
          (throw (ex-info "Unknown library compiler option" {:option arg})))))))

(def usage
  (str "zil-library [--root DIR]* [--out DIR] [--manifest FILE] "
       "[--namespace PREFIX] [--check] [--clean-stale]"))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (compile-tree! options)]
          (println (pr-str (select-keys report [:schema :ok :check-only :output-root])))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)] (prn data)))
      (System/exit 2))))
