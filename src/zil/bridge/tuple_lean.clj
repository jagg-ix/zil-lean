(ns zil.bridge.tuple-lean
  "Translate original ZIL tuple facts into native ZIL Lean declarations."
  (:gen-class)
  (:require [clojure.java.io :as io]
            [clojure.pprint :as pp]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.relational-ir :as rir]))

(def ^:private lean-reserved
  #{"abbrev" "axiom" "by" "class" "def" "deriving" "do" "else" "end"
    "example" "if" "import" "in" "inductive" "instance" "let" "match"
    "namespace" "open" "private" "protected" "set_option" "structure"
    "theorem" "variable" "where" "with"})

(defn- token-text
  [value field]
  (let [text (cond
               (string? value) value
               (keyword? value) (name value)
               (symbol? value) (name value)
               :else nil)]
    (when (or (nil? text) (str/blank? (str/trim text)))
      (throw (ex-info "Tuple-to-Lean expects named string-like terms"
                      {:field field :value value})))
    (str/trim text)))

(defn- sanitize-segment
  [segment previous]
  (let [clean (str/replace segment #"[^A-Za-z0-9_]" "_")
        numbered (if (re-matches #"^[0-9].*" clean)
                   (str (if (= previous "user") "u" "n") clean)
                   clean)
        safe (if (contains? lean-reserved numbered)
               (str numbered "_")
               numbered)]
    (when (str/blank? safe)
      (throw (ex-info "Tuple term contains an empty Lean name segment"
                      {:segment segment})))
    safe))

(defn term->lean-name
  "Convert a ZIL term such as `doc:readme` or `user:10` into a Lean name."
  [value]
  (let [raw (token-text value :term)
        parts (->> (str/split raw #"[:./]+")
                   (remove str/blank?)
                   vec)]
    (when (empty? parts)
      (throw (ex-info "Tuple term cannot be converted to a Lean name"
                      {:value value})))
    (loop [remaining parts
           previous nil
           out []]
      (if-let [part (first remaining)]
        (let [segment (sanitize-segment part previous)]
          (recur (next remaining) segment (conj out segment)))
        (str/join "." out)))))

(defn- split-camel-token
  [value]
  (let [text (str value)
        first-pass (str/replace text #"([A-Z]+)([A-Z][a-z])" "$1_$2")
        second-pass (str/replace first-pass #"([a-z0-9])([A-Z])" "$1_$2")]
    (str/split second-pass #"[^A-Za-z0-9]+")))

(defn- identifier-parts
  [value]
  (->> (split-camel-token (token-text value :identifier))
       (remove str/blank?)
       vec))

(defn- upper-first
  [text]
  (if (str/blank? text)
    ""
    (str (str/upper-case (subs text 0 1)) (subs text 1))))

(defn- relation->lean-ident
  [relation]
  (let [parts (identifier-parts relation)
        head (str/lower-case (or (first parts) "relation"))
        tail (map #(upper-first (str/lower-case %)) (rest parts))
        candidate (apply str head tail)]
    (sanitize-segment candidate nil)))

(defn- relation->lean-name
  [relation]
  (str "`zil." (relation->lean-ident relation)))

(defn- namespace-segment
  [part]
  (let [tokens (identifier-parts part)
        candidate (if (seq tokens)
                    (apply str (map #(upper-first (str/lower-case %)) tokens))
                    "Generated")]
    (sanitize-segment candidate nil)))

(defn- sanitize-namespace
  [namespace]
  (let [segments (->> (str/split (or namespace "") #"\.")
                      (remove str/blank?)
                      (map namespace-segment)
                      vec)]
    (if (seq segments)
      (str/join "." segments)
      "Zil.Generated.TupleFacts")))

(defn- source-stem
  [path]
  (let [filename (.getName (io/file path))]
    (str/replace filename #"\.[^.]+$" "")))

(defn- default-namespace
  [path module]
  (let [source (if (str/blank? module) (source-stem path) module)
        segments (->> (str/split source #"[.:/]+")
                      (remove str/blank?)
                      (map namespace-segment))]
    (str/join "." (concat ["Zil" "Generated"] segments))))

(defn- split-userset
  [subject]
  (when (string? subject)
    (let [idx (.lastIndexOf ^String subject "#")]
      (when (and (pos? idx) (< idx (dec (count subject))))
        (let [base (subs subject 0 idx)
              selector (subs subject (inc idx))]
          (when (re-matches #"[A-Za-z0-9_.:-]+" selector)
            {:source subject
             :base base
             :selector (keyword selector)}))))))

(defn- validate-input!
  [{:keys [facts rules queries declarations]}]
  (when (empty? facts)
    (throw (ex-info "No tuple facts found" {})))
  (when (seq rules)
    (throw (ex-info "Tuple-to-Lean currently accepts tuple facts only; rules are handled by native ZIL Lean rules"
                    {:rule_count (count rules)})))
  (when (seq queries)
    (throw (ex-info "Tuple-to-Lean currently accepts tuple facts only; queries are handled by native ZIL Lean queries"
                    {:query_count (count queries)})))
  (when (seq declarations)
    (throw (ex-info "Tuple-to-Lean currently accepts MODULE and tuple facts; standard-library declarations require a dedicated mapping"
                    {:declaration_count (count declarations)})))
  (doseq [{:keys [object relation subject attrs] :as fact} facts]
    (token-text object :object)
    (token-text subject :subject)
    (when-not (keyword? relation)
      (throw (ex-info "Tuple relation must be a keyword after parsing" {:fact fact})))
    (when (seq attrs)
      (throw (ex-info "Tuple attributes do not yet have a native `zil_fact` encoding"
                      {:fact fact :attrs attrs}))))
  true)

(defn- canonical-node-value
  [term]
  (when-not (= :node (:term/kind term))
    (throw (ex-info "Tuple-to-Lean currently emits ground tuple facts only"
                    {:term term})))
  (:term/value term))

(defn- render-tuple-value
  [index tuple]
  (let [object-name (term->lean-name (canonical-node-value (:tuple/object tuple)))
        outer-name (relation->lean-name (:relation tuple))
        subject (:tuple/subject tuple)
        body (case (:term/kind subject)
               :direct
               (str "  Zil.TupleExpr.direct\n"
                    "    (.ground `" object-name ")\n"
                    "    " outer-name "\n"
                    "    (.ground `" (term->lean-name
                                      (canonical-node-value (:term subject))) ")")

               :userset
               (str "  Zil.TupleExpr.withUserset\n"
                    "    (.ground `" object-name ")\n"
                    "    " outer-name "\n"
                    "    ⟨`" (term->lean-name
                              (canonical-node-value (:userset/object subject))) "⟩\n"
                    "    " (relation->lean-name (:userset/relation subject)))

               (throw (ex-info "Unknown canonical tuple subject"
                               {:tuple tuple :subject subject})))]
    (str "private def sourceTuple" index " : Zil.TupleExpr :=\n" body)))

(defn- render-source-tuples
  [tuples]
  (let [definitions (map-indexed render-tuple-value tuples)
        names (map-indexed (fn [idx _] (str "sourceTuple" idx)) tuples)]
    (str (str/join "\n\n" definitions)
         "\n\ndef sourceTuples : Array Zil.TupleExpr := #[\n  "
         (str/join ",\n  " names)
         "\n]")))

(defn- render-fact
  [{:keys [object relation subject]}]
  (let [userset (split-userset subject)
        target (or (:base userset) subject)
        source-comment (when userset
                         (str "-- Source userset: " (:source userset)
                              " (follow relation `" (name (:selector userset)) "`)\n"))]
    (str source-comment
         "zil_fact\n"
         "  node(" (term->lean-name object) ")\n"
         "    ⟶[" (relation->lean-ident relation) "]\n"
         "  node(" (term->lean-name target) ")")))

(defn- userset-pairs
  [facts]
  (->> facts
       (keep (fn [{:keys [relation subject]}]
               (when-let [userset (split-userset subject)]
                 {:outer relation :inner (:selector userset)})))
       distinct
       vec))

(defn- rule-name
  [outer inner]
  (str (relation->lean-ident outer)
       "Via"
       (upper-first (relation->lean-ident inner))))

(defn- render-userset-rule
  [{:keys [outer inner]}]
  (let [outer-id (relation->lean-ident outer)
        inner-id (relation->lean-ident inner)]
    (str "zil_theorem_rule " (rule-name outer inner) "\n"
         "  {object userset subject : Zil.Node}\n"
         "  (hOuter : object ⟶[" outer-id "] userset)\n"
         "  (hInner : userset ⟶[" inner-id "] subject)\n"
         "  : object ⟶[" outer-id "] subject")))

(defn render-lean4-module
  "Render a native ZIL Lean module from parsed tuple facts."
  [{:keys [namespace source-path facts tuples]}]
  (let [pairs (userset-pairs facts)
        source-text (render-source-tuples tuples)
        fact-text (str/join "\n\n" (map render-fact facts))
        rule-text (str/join "\n\n" (map render-userset-rule pairs))]
    (str "/-\n"
         "Generated from original ZIL tuple syntax.\n"
         "Source: " source-path "\n"
         "-/\n\n"
         "import Zil\n\n"
         "namespace " namespace "\n\n"
         "/- Lossless original tuple values -/\n\n"
         source-text
         "\n\n/- Lowered facts for the current Horn engine -/\n\n"
         fact-text
         (when (seq pairs)
           (str "\n\n/- Userset expansion rules -/\n\n" rule-text))
         "\n\nend " namespace "\n")))

(defn export-tuples->lean4
  "Translate tuple facts from a `.zc` file into native ZIL Lean source.

  A MODULE declaration is optional. Options:
  - :namespace    generated Lean namespace
  - :output-path write the generated Lean module to this path"
  ([path]
   (export-tuples->lean4 path {}))
  ([path {:keys [namespace output-path]}]
   (let [{:keys [module facts] :as parsed} (core/parse-program (slurp path))
         _ (validate-input! parsed)
         tuples (mapv rir/from-legacy-tuple facts)
         namespace* (sanitize-namespace
                     (or namespace (default-namespace path module)))
         pairs (userset-pairs facts)
         text (render-lean4-module {:namespace namespace*
                                    :source-path path
                                    :facts facts
                                    :tuples tuples})]
     (when output-path
       (let [output-file (io/file output-path)
             parent (.getParentFile output-file)]
         (when parent (.mkdirs parent))
         (spit output-file text)))
     {:ok true
      :path path
      :module module
      :namespace namespace*
      :tuple_count (count tuples)
      :fact_count (count facts)
      :userset_rule_count (count pairs)
      :usersets (mapv (fn [{:keys [outer inner]}]
                        {:outer (name outer)
                         :inner (name inner)
                         :rule (rule-name outer inner)})
                      pairs)
      :output_path output-path
      :text text})))

(defn -main
  [& args]
  (let [[input-path output-path namespace] args]
    (when-not input-path
      (binding [*out* *err*]
        (println "Usage: zil-tuples-lean <input.zc> [output.lean|-] [namespace]"))
      (System/exit 2))
    (try
      (let [write-path (when (and output-path (not= output-path "-")) output-path)
            report (export-tuples->lean4
                    input-path
                    (cond-> {}
                      write-path (assoc :output-path write-path)
                      namespace (assoc :namespace namespace)))]
        (if write-path
          (pp/pprint (dissoc report :text))
          (print (:text report))))
      (catch clojure.lang.ExceptionInfo e
        (binding [*out* *err*]
          (println (.getMessage e))
          (pp/pprint (ex-data e)))
        (System/exit 2)))))
