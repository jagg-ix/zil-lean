(ns zil.port.native-macro
  "Compose Clojure-style macro libraries and execute the native Lean frontend."
  (:gen-class)
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.preprocess :as preprocess])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files Path Paths StandardCopyOption)
           (java.security MessageDigest)))

(def default-native-command ["lake" "exe" "zil" "--"])
(def parity-schema "ZIL-MACRO-PARITY/1")

(defn- absolute-path ^Path [value]
  (.normalize (.toAbsolutePath (Paths/get (str value) (make-array String 0)))))

(defn- path-string [^Path path]
  (str/replace (.toString path) "\\" "/"))

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest))))

(defn run-command
  [{:keys [command directory environment]}]
  (let [builder (ProcessBuilder. ^java.util.List (vec command))
        _ (when directory (.directory builder (io/file directory)))
        env (.environment builder)
        _ (doseq [[key value] environment] (.put env (str key) (str value)))
        process (.start builder)
        out-future (future (slurp (.getInputStream process)))
        err-future (future (slurp (.getErrorStream process)))
        exit (.waitFor process)]
    {:exit exit :out @out-future :err @err-future :command (vec command)}))

(defn compose-model
  "Compose sorted non-recursive `lib/*.zc` files before one model.

  With no explicit `lib-dir`, the nearest ancestor `lib/` directory is used,
  matching `zil.preprocess/preprocess-model`."
  [model-path {:keys [lib-dir]}]
  (preprocess/preprocess-model
   model-path
   (cond-> {}
     lib-dir (assoc :lib-dir lib-dir))))

(defn prepare-source
  "Return the exact source text that native and Clojure consumers should use.

  Sources with no library and direct members of the selected `lib/` directory
  remain standalone. Other files are composed with sorted, non-recursive
  library sources discovered by `preprocess-model`."
  [source-path {:keys [lib-dir] :as options}]
  (let [source-file (.getCanonicalFile (io/file source-path))
        resolved (preprocess/resolve-lib-dir source-path lib-dir)
        resolved-file (some-> resolved .getCanonicalFile)
        direct-library-member?
        (and resolved-file
             (= resolved-file (.getCanonicalFile (.getParentFile source-file))))]
    (if (or (nil? resolved-file) direct-library-member?)
      (let [text (slurp source-file)]
        {:ok true
         :model (.getCanonicalPath source-file)
         :lib_dir (some-> resolved-file .getCanonicalPath)
         :lib_files []
         :composed false
         :text text
         :source_sha256 (sha256 text)})
      (let [composition (compose-model source-path options)]
        (assoc composition
               :composed (boolean (seq (:lib_files composition)))
               :source_sha256 (sha256 (:text composition)))))))

(defn- write-atomic! [path text]
  (let [target (absolute-path path)
        parent (.getParent target)
        _ (when parent
            (Files/createDirectories parent
                                     (make-array java.nio.file.attribute.FileAttribute 0)))
        temporary (Files/createTempFile parent ".zil-macro-" ".tmp"
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

(defn- native-request
  [{:keys [native-command]
    :or {native-command default-native-command}}
   mode temporary namespace]
  (let [base (into (vec native-command) [mode (path-string temporary) "-"])]
    (if (and (= mode "compile") (not (str/blank? namespace)))
      (conj base namespace)
      base)))

(defn invoke-native
  "Run the native frontend over already prepared source text.

  `mode` may be any native source operation such as `compile`, `expand`, or
  `conformance`. Output is captured from stdout."
  [{:keys [runner temp-root directory]
    :or {runner run-command}
    :as options}
   mode source namespace]
  (let [root (absolute-path (or temp-root (System/getProperty "java.io.tmpdir")))
        _ (Files/createDirectories root
                                   (make-array java.nio.file.attribute.FileAttribute 0))
        temporary (Files/createTempFile root "zil-macro-composed-" ".zc"
                                        (make-array java.nio.file.attribute.FileAttribute 0))]
    (try
      (Files/writeString temporary source StandardCharsets/UTF_8
                         (into-array java.nio.file.OpenOption []))
      (let [command (native-request options mode temporary namespace)
            result (runner {:command command :directory directory :environment {}})]
        (assoc result :command (:command result command)))
      (finally
        (Files/deleteIfExists temporary)))))

(defn compile-model!
  [{:keys [model output namespace] :as options}]
  (let [composition (prepare-source model options)
        result (invoke-native options "compile" (:text composition) namespace)]
    (when-not (zero? (:exit result))
      (throw (ex-info "Native macro compilation failed"
                      {:exit (:exit result)
                       :error (str/trim (or (:err result) ""))
                       :command (:command result)})))
    (if (or (nil? output) (= output "-"))
      (print (:out result))
      (write-atomic! output (:out result)))
    {:ok true
     :mode :compile
     :model (:model composition)
     :lib_dir (:lib_dir composition)
     :lib_files (:lib_files composition)
     :composed (:composed composition)
     :source_sha256 (:source_sha256 composition)
     :output (or output "-")
     :namespace namespace
     :command (:command result)}))

(defn expand-model!
  [{:keys [model output] :as options}]
  (let [composition (prepare-source model options)
        result (invoke-native options "expand" (:text composition) nil)]
    (when-not (zero? (:exit result))
      (throw (ex-info "Native macro expansion failed"
                      {:exit (:exit result)
                       :error (str/trim (or (:err result) ""))
                       :command (:command result)})))
    (if (or (nil? output) (= output "-"))
      (print (:out result))
      (write-atomic! output (:out result)))
    {:ok true
     :mode :expand
     :model (:model composition)
     :lib_dir (:lib_dir composition)
     :lib_files (:lib_files composition)
     :composed (:composed composition)
     :source_sha256 (:source_sha256 composition)
     :output (or output "-")
     :command (:command result)}))

(defn- normalized-lines [text]
  (->> (str/split-lines (or text ""))
       (map str/trim)
       (remove str/blank?)
       vec))

(defn parity-report
  "Compare Clojure and native Lean macro expansion over one prepared source."
  [{:keys [model] :as options}]
  (let [composition (prepare-source model options)
        legacy-lines (vec (core/expand-macros (:text composition)))
        native-result (invoke-native options "expand" (:text composition) nil)
        native-lines (if (zero? (:exit native-result))
                       (normalized-lines (:out native-result))
                       [])
        legacy-only (vec (remove (set native-lines) legacy-lines))
        native-only (vec (remove (set legacy-lines) native-lines))
        exact (= legacy-lines native-lines)
        report (sorted-map
                :schema parity-schema
                :ok (and (zero? (:exit native-result)) exact)
                :model (:model composition)
                :lib_dir (:lib_dir composition)
                :lib_files (:lib_files composition)
                :composed (:composed composition)
                :source_sha256 (:source_sha256 composition)
                :legacy_count (count legacy-lines)
                :native_count (count native-lines)
                :exact exact
                :legacy_only legacy-only
                :native_only native-only
                :native_exit (:exit native-result)
                :native_error (str/trim (or (:err native-result) ""))
                :native_command (:command native-result))]
    report))

(defn parity-model!
  [{:keys [output] :as options}]
  (let [report (parity-report options)
        text (str (pr-str report) "\n")]
    (if (or (nil? output) (= output "-"))
      (print text)
      (write-atomic! output text))
    report))

(def usage
  (str "zil-macro-native compile <model.zc> [--output FILE|-] [--namespace NAME] [--lib DIR]\n"
       "zil-macro-native expand <model.zc> [--output FILE|-] [--lib DIR]\n"
       "zil-macro-native parity <model.zc> [--output FILE|-] [--lib DIR]"))

(defn- option-value! [remaining flag]
  (or (second remaining)
      (throw (ex-info "Missing macro option value" {:option flag}))))

(defn- parse-options [mode model args]
  (loop [remaining (seq args)
         options {:mode mode :model model}]
    (if-not remaining
      options
      (case (first remaining)
        "--output" (recur (nnext remaining)
                          (assoc options :output (option-value! remaining "--output")))
        "--namespace" (recur (nnext remaining)
                             (assoc options :namespace (option-value! remaining "--namespace")))
        "--lib" (recur (nnext remaining)
                       (assoc options :lib-dir (option-value! remaining "--lib")))
        "--help" (assoc options :help true)
        (throw (ex-info "Unknown macro option" {:option (first remaining)}))))))

(defn- parse-cli [args]
  (let [[mode model & tail] args]
    (if (or (nil? mode) (= mode "--help") (= mode "-h"))
      {:help true}
      (do
        (when-not (contains? #{"compile" "expand" "parity"} mode)
          (throw (ex-info "Unknown macro command" {:command mode})))
        (when (str/blank? model)
          (throw (ex-info "Macro command requires a model path" {:command mode})))
        (let [options (parse-options mode model tail)]
          (when (and (not= mode "compile") (:namespace options))
            (throw (ex-info "--namespace is valid only for compile" {:command mode})))
          options)))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (case (:mode options)
          "compile" (do (compile-model! options) (System/exit 0))
          "expand" (do (expand-model! options) (System/exit 0))
          "parity" (let [report (parity-model! options)]
                     (System/exit (if (:ok report) 0 1))))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)] (println (pr-str data))))
      (System/exit 2))))
