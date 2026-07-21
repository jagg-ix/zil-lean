(ns zil.embedded
  "Portable, read-only extraction of explicitly delimited ZIL comment blocks."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.preprocess :as preprocess])
  (:import [java.security MessageDigest]))

(def ^:private language-by-extension
  {"lean" :lean4, "py" :python, "clj" :clojure, "cljs" :clojure,
   "cljc" :clojure, "rs" :rust, "md" :markdown})

(defn- extension [path]
  (some-> (re-find #"\.([^.]+)$" (str path)) second str/lower-case))

(defn language-for [path]
  (get language-by-extension (extension path) :unknown))

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) "UTF-8"))]
    (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest))))

(defn- strip-comment-prefix [line]
  (-> line str/trim
      (str/replace #"^(?:/\*+|\*+/|\*|//+|;;+|#+)\s*" "")
      (str/replace #"\s*(?:\*/)?$" "") str/trim))

(defn- declaration-match [language line]
  (let [match (case language
                :lean4 (re-find #"^\s*(theorem|def|opaque|axiom|inductive|structure|class|abbrev)\s+([A-Za-z_][A-Za-z0-9_'.]*)" line)
                :python (re-find #"^\s*(?:async\s+)?(def|class)\s+([A-Za-z_][A-Za-z0-9_]*)" line)
                :clojure (re-find #"^\s*\((defn|defn-|def|defmacro)\s+([^\s\[\]()]+)" line)
                :rust (re-find #"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(fn|struct|enum|trait)\s+([A-Za-z_][A-Za-z0-9_]*)" line)
                nil)]
    (when match {:kind (str/lower-case (nth match 1)) :name (nth match 2)})))

(defn- target-prefix [language]
  (case language :lean4 "lean:" :python "python:" :clojure "clojure:"
                 :rust "rust:" :markdown "markdown:" "host:"))

(defn- lean-namespace-at [lines marker-index]
  (reduce
   (fn [stack line]
     (if-let [[_ namespace] (re-find #"^\s*namespace\s+([A-Za-z_][A-Za-z0-9_'.]*)\s*$" line)]
       (conj stack namespace)
       (if-let [[_ ended] (re-find #"^\s*end\s+([A-Za-z_][A-Za-z0-9_'.]*)\s*$" line)]
         (if (= ended (peek stack)) (pop stack) stack)
         stack)))
   [] (take marker-index lines)))

(defn- resolve-self [lines language after-line explicit-target namespace-stack]
  (let [declaration (some #(declaration-match language %) (drop after-line lines))]
    (if (and explicit-target (not= explicit-target "self"))
      {:target explicit-target :declaration_kind (:kind declaration)}
      (if declaration
      (let [name (:name declaration)
            qualified (if (or (not= language :lean4) (str/includes? name ".")
                              (empty? namespace-stack))
                        name
                        (str (str/join "." namespace-stack) "." name))]
      {:target (str (target-prefix language) qualified)
       :declaration_kind (:kind declaration)}
      )
      (throw (ex-info "Embedded ZIL target=self has no following host declaration"
                      {:code :attachment :language language :after_line after-line}))))))

(defn- marker-target [line]
  (when-let [[_ value] (re-find #"@zil(?:\s+target\s*=\s*([^\s]+))?" line)]
    (or value "self")))

(defn- canonical-statement [statement target]
  (let [line (str/trim statement)]
    (when-not (str/ends-with? line ".")
      (throw (ex-info "Embedded ZIL statements must end with '.'"
                      {:code :syntax :statement statement})))
    (let [body (subs line 0 (dec (count line)))]
      (when-not (re-matches #"[^#\s]+#[A-Za-z_][A-Za-z0-9_]*@[^\s]+" body)
        (throw (ex-info "Initial embedded scanner accepts canonical ground facts only"
                        {:code :syntax :statement statement})))
      (str (str/replace-first body #"^self(?=#)"
                              (java.util.regex.Matcher/quoteReplacement target)) "."))))

(defn- macro-environment [macro-text]
  (if (str/blank? (or macro-text ""))
    {}
    (:macros (core/collect-macro-definitions (core/preprocess-lines macro-text)))))

(defn- substitute-context [statement context]
  (reduce-kv
   (fn [text key value]
     (str/replace text
                  (re-pattern (str "(?<![A-Za-z0-9_.:-])" key "(?![A-Za-z0-9_.:-])"))
                  (java.util.regex.Matcher/quoteReplacement value)))
   statement context))

(defn- expand-statements [statements context macros]
  (let [expanded (core/expand-macro-uses
                  (mapv #(substitute-context % context) statements) macros)]
    (mapv #(canonical-statement % (get context "self")) expanded)))

(defn- module-name-for [path language]
  (let [base (-> (str path)
                 (str/replace #"\\" "/")
                 (str/replace #"\.[^.]+$" "")
                 (str/replace #"/+" "."))]
    (str (case language :lean4 "lean_module:" :python "python_module:"
                        :clojure "clojure_module:" :rust "rust_module:" "module:")
         (str/replace base #"^\." ""))))

(defn- namespace-for [target language]
  (let [plain (subs target (min (count target) (count (target-prefix language))))
        pieces (str/split plain #"\.")]
    (str (case language :lean4 "lean_namespace:" :python "python_namespace:"
                        :clojure "clojure_namespace:" :rust "rust_namespace:" "namespace:")
         (if (> (count pieces) 1) (str/join "." (butlast pieces)) "root"))))

(defn scan-text
  "Extract blocks from one host source. `self` attaches to the first following declaration."
  ([path text] (scan-text path text {}))
  ([path text {:keys [macro-text project]}]
  (let [lines (str/split-lines text)
        language (language-for path)
        source-hash (str "sha256:" (sha256 text))
        macro-revision (str "sha256:" (sha256 (or macro-text "")))
        macros (macro-environment macro-text)]
    (loop [index 0, ordinal 0, blocks []]
      (if (>= index (count lines))
        {:path (str path) :language language :source_hash source-hash :blocks blocks}
        (if-let [requested-target (marker-target (nth lines index))]
          (let [end-index (first (filter #(re-find #"@endzil" (nth lines %))
                                         (range (inc index) (count lines))))]
            (when-not end-index
              (throw (ex-info "Embedded @zil block has no @endzil marker"
                              {:code :syntax :path (str path) :start_line (inc index)})))
            (let [{:keys [target declaration_kind]}
                  (resolve-self lines language (inc end-index) requested-target
                                (if (= language :lean4)
                                  (lean-namespace-at lines index) []))
                  module-name (module-name-for path language)
                  namespace (namespace-for target language)
                  project-name (or project (.getName (io/file (or (.getParent (io/file path)) "."))))
                  source-span (str "source_span:" path ":" (inc index) "-" (inc end-index))
                  context {"self" target
                           "file" (str "file:" path)
                           "module" module-name
                           "namespace" namespace
                           "project" (str "project:" project-name)
                           "revision" source-hash
                           "declaration_kind" (str (name language) "_kind:" (or declaration_kind "unknown"))
                           "source_span" source-span}
                  raw-statements (->> (subvec (vec lines) (inc index) end-index)
                                      (map strip-comment-prefix) (remove str/blank?) vec)
                  statements (expand-statements raw-statements context macros)
                  block-id (str "embedded:" (subs (sha256 (str path ":" ordinal)) 0 16))]
              (when (empty? statements)
                (throw (ex-info "Embedded @zil block is empty"
                                {:code :syntax :path (str path) :start_line (inc index)})))
              (recur (inc end-index) (inc ordinal)
                     (conj blocks (cond-> {:block_id block-id :target target
                                   :trust :asserted_annotation
                                   :start_line (inc index) :end_line (inc end-index)
                                   :source_hash source-hash
                                   :macro_revision macro-revision
                                   :module module-name :namespace namespace
                                   :project (str "project:" project-name)
                                   :source_span source-span
                                   :statements statements}
                                    declaration_kind (assoc :declaration_kind declaration_kind))))))
          (recur (inc index) ordinal blocks)))))))

(defn- source-files [path]
  (let [file (io/file path)]
    (cond
      (.isFile file) [file]
      (.isDirectory file) (->> (file-seq file) (filter #(.isFile %))
                               (filter #(contains? language-by-extension (extension (.getPath %))))
                               (sort-by #(.getPath %)))
      :else (throw (ex-info "Embedded scan path does not exist" {:code :io :path (str path)})))))

(defn- q [value] (pr-str (str value)))

(defn render-zil [reports module-name]
  (let [blocks (mapcat :blocks reports)
        facts (mapcat (fn [{:keys [block_id target trust start_line end_line source_hash macro_revision statements]}]
                        (concat [(str (q block_id) "#kind@" (q "embedded_zil_block") ".")
                                 (str (q block_id) "#target@" (q target) ".")
                                 (str (q block_id) "#trust@" (q (str "trust:" (name trust))) ".")
                                 (str (q block_id) "#source_hash@" (q source_hash) ".")
                                 (str (q block_id) "#macro_revision@" (q macro_revision) ".")
                                 (str (q block_id) "#start_line@" (q start_line) ".")
                                 (str (q block_id) "#end_line@" (q end_line) ".")]
                                statements)) blocks)]
    (str "MODULE " module-name ".\n\n"
         "// Generated read-only from explicit @zil/@endzil source annotations.\n"
         (str/join "\n" facts) (when (seq facts) "\n"))))

(defn- macro-text-for [source-file lib-dir]
  (->> (preprocess/collect-lib-zc-files (.getPath ^java.io.File source-file) lib-dir)
       (map slurp)
       (str/join "\n")))

(defn scan-path
  ([path] (scan-path path {}))
  ([path {:keys [module-name output-path lib-dir] :or {module-name "embedded.annotations"}}]
   (let [project-name (.getName (io/file path))
         reports (mapv #(scan-text (.getPath %) (slurp %)
                                  {:macro-text (macro-text-for % lib-dir)
                                   :project project-name})
                       (source-files path))
         text (render-zil reports module-name)
         _ (core/compile-program text)
         result {:ok true :path (str path) :module module-name
                 :file_count (count reports)
                 :block_count (reduce + (map #(count (:blocks %)) reports))
                 :reports reports :text text}]
     (when output-path (spit output-path text))
     result)))

(def snapshot-format "zil.embedded-snapshot.v0.1")

(defn snapshot-data
  "Create a deterministic, versioned baseline from a scan result."
  [scan-result]
  {:format snapshot-format
   :root (:path scan-result)
   :module (:module scan-result)
   :blocks (->> (:reports scan-result)
                (mapcat (fn [report]
                          (map #(assoc % :path (:path report)
                                       :language (name (:language report)))
                               (:blocks report))))
                (sort-by :block_id)
                vec)})

(defn write-snapshot! [scan-result output-path]
  (let [snapshot (snapshot-data scan-result)]
    (spit output-path (str (json/write-str snapshot :escape-slash false) "\n"))
    snapshot))

(defn read-snapshot [path]
  (let [snapshot (json/read-str (slurp path) :key-fn keyword)]
    (when-not (= snapshot-format (:format snapshot))
      (throw (ex-info "Unsupported embedded snapshot format"
                      {:code :validation :format (:format snapshot)})))
    snapshot))

(def ^:private drift-fields
  [[:source_hash :source_changed]
   [:macro_revision :macro_changed]
   [:target :target_changed]
   [:statements :expansion_changed]])

(defn drift-between
  "Compare two embedded snapshots by stable path/ordinal block identity."
  [baseline current]
  (let [before (into {} (map (juxt :block_id identity) (:blocks baseline)))
        after (into {} (map (juxt :block_id identity) (:blocks current)))
        before-ids (set (keys before))
        after-ids (set (keys after))
        removed (for [id (sort (set/difference before-ids after-ids))]
                  {:block_id id :kind :block_removed :before (get before id)})
        added (for [id (sort (set/difference after-ids before-ids))]
                {:block_id id :kind :block_added :after (get after id)})
        changed (for [id (sort (set/intersection before-ids after-ids))
                      [field kind] drift-fields
                      :let [old (get-in before [id field]) new (get-in after [id field])]
                      :when (not= old new)]
                  {:block_id id :kind kind :field field :before old :after new})
        differences (vec (concat removed added changed))]
    {:ok (empty? differences)
     :drift (boolean (seq differences))
     :baseline_format (:format baseline)
     :block_count_before (count before)
     :block_count_after (count after)
     :differences differences}))

(defn snapshot-path! [source-path output-path opts]
  (let [scan (scan-path source-path opts)
        snapshot (write-snapshot! scan output-path)]
    {:ok true :output output-path :format (:format snapshot)
     :block_count (count (:blocks snapshot))}))

(defn drift-check [source-path baseline-path opts]
  (let [baseline (read-snapshot baseline-path)
        current (snapshot-data (scan-path source-path opts))]
    (drift-between baseline current)))
