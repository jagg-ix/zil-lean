(ns zil.bridge.tla
  "Bridge helpers to export ZIL LTS_ATOM declarations to parse-friendly TLA+."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core]))

(def ^:private acronym-parts
  #{"api" "db" "fsm" "id" "ip" "l3" "ssh" "tcp" "tls" "udp" "ui" "vpn" "ws" "x11"})

(defn- token->name
  [v]
  (cond
    (keyword? v) (name v)
    (symbol? v) (name v)
    :else (str v)))

(defn- tla-escape
  [s]
  (-> (str s)
      (str/replace "\\" "\\\\")
      (str/replace "\"" "\\\"")))

(defn- tla-string
  [s]
  (str "\"" (tla-escape s) "\""))

(defn- zc-file?
  [^java.io.File f]
  (and (.isFile f)
       (str/ends-with? (.getName f) ".zc")))

(defn collect-zc-files
  "Collect .zc files from one file path or recursively from a directory."
  [path]
  (let [f (io/file path)]
    (cond
      (not (.exists f)) []
      (.isFile f) (if (zc-file? f) [(.getPath f)] [])
      (.isDirectory f) (->> (file-seq f)
                            (filter zc-file?)
                            (map #(.getPath ^java.io.File %))
                            sort
                            vec)
      :else [])))

(defn- tokenize-ident
  [s]
  (let [text (str s)
        s1 (str/replace text #"([A-Z]+)([A-Z][a-z])" "$1_$2")
        s2 (str/replace s1 #"([a-z0-9])([A-Z])" "$1_$2")]
    (->> (str/split s2 #"[^A-Za-z0-9]+")
         (remove str/blank?)
         vec)))

(defn- pascalize-part
  [part]
  (let [token (str part)
        lower (str/lower-case token)]
    (cond
      (str/blank? token) ""
      (contains? acronym-parts lower) (str/upper-case lower)
      (re-matches #"[0-9]+" token) token
      (re-matches #"[A-Z][A-Za-z0-9]*" token) token
      :else (str (str/upper-case (subs lower 0 1))
                 (subs lower 1)))))

(defn- to-pascal-case
  [s]
  (let [parts (tokenize-ident s)]
    (if (empty? parts)
      "Actor"
      (apply str (map pascalize-part parts)))))

(defn- to-lower-camel-case
  [s]
  (let [parts (tokenize-ident s)]
    (if (empty? parts)
      "actor"
      (let [head (str/lower-case (first parts))
            tail (map pascalize-part (rest parts))]
        (apply str head tail)))))

(defn- sanitize-module-id
  [s]
  (let [text (or s "ZilLTSBridge")
        cleaned (str/replace text #"[^A-Za-z0-9_]" "_")]
    (if (re-matches #"^[0-9].*" cleaned)
      (str "M_" cleaned)
      cleaned)))

(defn- parse-zc-file
  [path]
  (let [text (slurp path)
        parsed (core/parse-program text)
        mod (:module parsed)]
    (when (str/blank? mod)
      (throw (ex-info "Program must define MODULE <name> for TLA export."
                      {:file path})))
    parsed))

(defn- normalize-transition
  [[k v]]
  (let [[from-state label] k
        [to-state effect] v]
    {:from (token->name from-state)
     :label (token->name label)
     :to (token->name to-state)
     :effect (when effect (token->name effect))}))

(defn- transition-sort-key
  [{:keys [from label to effect]}]
  [from label to (or effect "")])

(defn- walk-trace-skeleton
  [initial transitions]
  (let [edges (vec (sort-by transition-sort-key transitions))
        outgoing (group-by :from edges)
        max-steps (max 1 (* 2 (count edges)))]
    (loop [current initial
           used #{}
           steps []
           n 0]
      (if (or (>= n max-steps) (empty? edges))
        steps
        (let [out (vec (sort-by transition-sort-key (get outgoing current [])))
              candidate (or (first (remove #(contains? used [(:from %) (:label %) (:to %)]) out))
                            (first out))]
          (if (nil? candidate)
            steps
            (recur (:to candidate)
                   (conj used [(:from candidate) (:label candidate) (:to candidate)])
                   (conj steps (:label candidate))
                   (inc n))))))))

(defn- normalize-lts-actor
  [{:keys [file module declaration]}]
  (let [{:keys [name attrs]} declaration
        actor-id (or (:actor attrs) name)
        actor-key (token->name (or (:actor_key attrs) (to-lower-camel-case actor-id)))
        actor-prefix (sanitize-module-id (to-pascal-case (token->name actor-id)))
        states (->> (set (map token->name (or (:states attrs) #{})))
                    sort
                    vec)
        initial (token->name (:initial attrs))
        transitions (->> (or (:transitions attrs) {})
                         (map normalize-transition)
                         (sort-by transition-sort-key)
                         vec)
        trace-labels (walk-trace-skeleton initial transitions)]
    {:file file
     :module module
     :name name
     :actor-prefix actor-prefix
     :actor-key actor-key
     :states states
     :initial initial
     :transitions transitions
     :trace-labels trace-labels}))

(defn- render-string-set
  [values]
  (if (empty? values)
    "{}"
    (str "{\n"
         (str/join ",\n" (map #(str "  " (tla-string %)) values))
         "\n}")))

(defn- render-transition-set
  [rows]
  (if (empty? rows)
    "{}"
    (str "{\n"
         (str/join
          ",\n"
          (map (fn [{:keys [from label to]}]
                 (str "  << "
                      (tla-string from) ", "
                      (tla-string label) ", "
                      (tla-string to)
                      " >>"))
               rows))
         "\n}")))

(defn- render-effect-set
  [rows]
  (let [with-effect (vec (filter :effect rows))]
    (if (empty? with-effect)
      nil
      (str "{\n"
           (str/join
            ",\n"
            (map (fn [{:keys [from label to effect]}]
                   (str "  << "
                        (tla-string from) ", "
                        (tla-string label) ", "
                        (tla-string to) ", "
                        (tla-string effect)
                        " >>"))
                 with-effect))
           "\n}"))))

(defn- render-trace-seq
  [actor-key labels]
  (if (empty? labels)
    "<< >>"
    (str "<<\n"
         (str/join
          ",\n"
          (map (fn [label]
                 (str "  << " (tla-string actor-key) ", " (tla-string label) " >>"))
               labels))
         "\n>>")))

(defn- render-system-trace
  [actors]
  (let [rows (vec (mapcat (fn [{:keys [actor-key trace-labels]}]
                            (map (fn [label] [actor-key label]) trace-labels))
                          actors))]
    (if (empty? rows)
      "<< >>"
      (str "<<\n"
           (str/join
            ",\n"
            (map (fn [[actor-key label]]
                   (str "  << " (tla-string actor-key) ", " (tla-string label) " >>"))
                 rows))
           "\n>>"))))

(defn- render-actor-block
  [{:keys [actor-prefix states initial transitions actor-key trace-labels]}]
  (let [effects (render-effect-set transitions)]
    (str
     actor-prefix "States == " (render-string-set states) "\n\n"
     actor-prefix "Initial == " (tla-string initial) "\n\n"
     actor-prefix "Transitions == " (render-transition-set transitions) "\n\n"
     (when effects
       (str actor-prefix "TransitionEffects == " effects "\n\n"))
     actor-prefix "CanonicalTrace == " (render-trace-seq actor-key trace-labels) "\n")))

(defn- duplicate-prefixes
  [actors]
  (->> actors
       (group-by :actor-prefix)
       (keep (fn [[prefix xs]]
               (when (> (count xs) 1)
                 prefix)))
       sort
       vec))

(declare collect-lts-vocabulary)

(defn render-tla-module
  "Render parse-friendly TLA module text from normalized actor entries."
  [{:keys [module-name actors include-system-trace?]
    :or {include-system-trace? true}}]
  (let [dup-prefixes (duplicate-prefixes actors)]
    (when (seq dup-prefixes)
      (throw (ex-info "Duplicate actor prefixes detected while rendering TLA module."
                      {:duplicates dup-prefixes})))
    (str
     "---------------------------- MODULE " (sanitize-module-id module-name) " -----------------------------\n"
     "(*\n"
     "Generated by `clojure -M -m zil.cli export-tla` from ZIL LTS_ATOM declarations.\n"
     "*)\n\n"
     "EXTENDS Sequences, FiniteSets, TLC\n\n"
     (str/join "\n" (map render-actor-block (sort-by :actor-prefix actors)))
     (when include-system-trace?
       (str "\nCanonicalSystemTrace == " (render-system-trace (sort-by :actor-prefix actors)) "\n"))
     "\n=============================================================================\n")))

(defn export-lts->tla
  "Export LTS_ATOM declarations in .zc path (file or directory) to TLA text.

  Options:
  - :module-name         override TLA module name
  - :output-path         write output to file path (if omitted, only :text is returned)
  - :include-system-trace? include CanonicalSystemTrace (default true)"
  ([path]
   (export-lts->tla path {}))
  ([path {:keys [module-name output-path include-system-trace?]
          :or {include-system-trace? true}}]
   (let [{:keys [files modules actors]} (collect-lts-vocabulary path)
         module* (sanitize-module-id
                  (or module-name
                      (if (= 1 (count modules))
                        (str (first modules) "_LTSBridge")
                        "ZilLTSBridge")))
         text (render-tla-module {:module-name module*
                                  :actors actors
                                  :include-system-trace? include-system-trace?})]
     (when output-path
       (let [out-file (io/file output-path)
             parent (.getParentFile out-file)]
         (when parent
           (.mkdirs parent))
         (spit out-file text)))
     {:ok true
      :path path
      :files files
      :modules modules
      :module_name module*
      :actor_count (count actors)
      :actors (mapv #(select-keys % [:name :actor-prefix :actor-key :file]) actors)
      :output_path output-path
      :text text})))

(defn collect-lts-vocabulary
  "Collect normalized actor vocabulary from LTS_ATOM declarations in .zc input.

  Returns:
  {:path ...
   :files [...]
   :modules [...]
   :actors [{:actor-prefix ... :actor-key ... :states [...] :initial ... :transitions [...]} ...]}"
  [path]
  (let [files (collect-zc-files path)]
    (when (empty? files)
      (throw (ex-info "No .zc files found in path."
                      {:path path})))
    (let [parsed-files
          (mapv (fn [f]
                  (try
                    {:file f :parsed (parse-zc-file f)}
                    (catch Exception e
                      (throw (ex-info "Failed to parse .zc file for vocabulary export."
                                      {:file f
                                       :error (.getMessage e)}
                                      e)))))
                files)
          lts-decls
          (vec (mapcat (fn [{:keys [file parsed]}]
                         (let [module (:module parsed)]
                           (for [decl (:declarations parsed)
                                 :when (= :lts_atom (:kind decl))]
                             {:file file
                              :module module
                              :declaration decl})))
                       parsed-files))]
      (when (empty? lts-decls)
        (throw (ex-info "No LTS_ATOM declarations found."
                        {:path path
                         :files files})))
      {:path path
       :files files
       :modules (->> parsed-files (map #(get-in % [:parsed :module])) distinct sort vec)
       :actors (mapv normalize-lts-actor lts-decls)})))
