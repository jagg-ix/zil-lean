(ns zil.relational-ir
  "Canonical relational intermediate representation shared by ZIL frontends.

  This namespace intentionally does not evaluate rules or queries. It normalizes
  tuple-like syntax into a stable representation that the standalone parser,
  embedded scanner, Lean frontend, query planner, and linters can share."
  (:require [clojure.string :as str]))

(def relation-aliases
  "Compatibility aliases accepted at frontend boundaries. Values are canonical,
  namespace-qualified relation keywords."
  {:requires_claim :zil/requiresClaim
   :requiresClaim :zil/requiresClaim
   :supported_by :zil/supportedBy
   :supportedBy :zil/supportedBy
   :depends_on :zil/dependsOn
   :dependsOn :zil/dependsOn
   :formalizes :zil/formalizes
   :requires :zil/requires})

(defn variable-token?
  [x]
  (and (string? x)
       (str/starts-with? x "?")
       (> (count x) 1)))

(defn canonical-relation
  "Normalize a relation keyword, symbol, or string.

  Known aliases are mapped to the `zil` namespace. Unknown unqualified names are
  preserved under `zil`; already-qualified names preserve their namespace."
  [relation]
  (let [k (cond
            (keyword? relation) relation
            (symbol? relation) (keyword (namespace relation) (name relation))
            (string? relation) (keyword relation)
            :else (throw (ex-info "Relation name must be keyword-like"
                                  {:relation relation})))
        alias-key (keyword (name k))]
    (or (get relation-aliases k)
        (get relation-aliases alias-key)
        (if (namespace k)
          k
          (keyword "zil" (name k))))))

(defn canonical-term
  "Classify a frontend token as a variable or a ground node/value."
  [x]
  (if (variable-token? x)
    {:term/kind :var
     :term/name (subs x 1)}
    {:term/kind :node
     :term/value x}))

(defn relation-expr
  "Construct a canonical relation expression.

  `source` is optional source data and must not affect semantic equality."
  ([subject relation object]
   (relation-expr subject relation object nil))
  ([subject relation object source]
   (cond-> {:ir/kind :relation
            :subject (canonical-term subject)
            :relation (canonical-relation relation)
            :object (canonical-term object)}
     source (assoc :source source))))

(defn from-legacy-atom
  "Convert the tuple map currently emitted by `zil.core/parse-atom`.

  Historical names `:object` and `:subject` are retained only at this adapter
  boundary. Canonical IR uses graph-oriented `:subject` and `:object`, matching
  the Lean notation `subject ⟶[relation] object`."
  [{legacy-object :object
    relation :relation
    legacy-subject :subject
    attrs :attrs
    neg? :neg?
    :as atom}]
  (when-not (and (contains? atom :object)
                 (contains? atom :relation)
                 (contains? atom :subject))
    (throw (ex-info "Legacy atom is missing object, relation, or subject"
                    {:atom atom})))
  (cond-> (relation-expr legacy-object relation legacy-subject)
    (seq attrs) (assoc :attrs attrs)
    (contains? atom :neg?) (assoc :neg? (boolean neg?))))

(defn from-native-map
  "Convert a frontend-neutral map shaped like Lean-native relation syntax."
  [{:keys [subject relation object source] :as expression}]
  (when-not (and (contains? expression :subject)
                 (contains? expression :relation)
                 (contains? expression :object))
    (throw (ex-info "Native relation map is incomplete"
                    {:expression expression})))
  (relation-expr subject relation object source))

(defn semantic-view
  "Remove source and frontend-only annotations for equivalence checks."
  [expression]
  (select-keys expression [:ir/kind :subject :relation :object :neg? :attrs]))

(defn equivalent?
  "True when two relation expressions have the same canonical semantics."
  [left right]
  (= (semantic-view left) (semantic-view right)))

(defn canonical-rule
  "Construct a canonical Horn-style rule from already normalized expressions."
  [{:keys [name variables premises conclusion trust source]}]
  (when-not (and name (seq premises) conclusion)
    (throw (ex-info "Rule requires name, at least one premise, and conclusion"
                    {:name name :premises premises :conclusion conclusion})))
  {:ir/kind :rule
   :rule/name (str name)
   :rule/variables (vec variables)
   :rule/premises (mapv semantic-view premises)
   :rule/conclusion (semantic-view conclusion)
   :rule/trust (or trust :graph-derived)
   :source source})

(defn split-userset-subject
  "Return `{base relation}` when a tuple subject has the form `object#relation`."
  [subject]
  (when (string? subject)
    (let [idx (.lastIndexOf ^String subject "#")]
      (when (and (pos? idx) (< idx (dec (count subject))))
        (let [base (subs subject 0 idx)
              relation (subs subject (inc idx))]
          (when (re-matches #"[A-Za-z0-9_.:-]+" relation)
            {:base base
             :relation (canonical-relation relation)}))))))

(defn canonical-tuple-subject
  "Preserve whether an original tuple subject is direct or a userset."
  [subject]
  (if-let [{:keys [base relation]} (split-userset-subject subject)]
    {:term/kind :userset
     :userset/object (canonical-term base)
     :userset/relation relation}
    {:term/kind :direct
     :term (canonical-term subject)}))

(defn tuple-expr
  "Construct a lossless canonical value for `object#relation@subject`."
  ([object relation subject]
   (tuple-expr object relation subject nil))
  ([object relation subject source]
   (cond-> {:ir/kind :tuple
            :tuple/object (canonical-term object)
            :relation (canonical-relation relation)
            :tuple/subject (canonical-tuple-subject subject)}
     source (assoc :source source))))

(defn from-legacy-tuple
  "Convert one `zil.core/parse-atom` result without collapsing usersets."
  [{:keys [object relation subject attrs] :as atom}]
  (when-not (and (contains? atom :object)
                 (contains? atom :relation)
                 (contains? atom :subject))
    (throw (ex-info "Legacy tuple is missing object, relation, or subject"
                    {:atom atom})))
  (cond-> (tuple-expr object relation subject)
    (seq attrs) (assoc :attrs attrs)))

(defn tuple-semantic-view
  "Semantic tuple data, retaining the direct/userset distinction."
  [tuple]
  (select-keys tuple [:ir/kind :tuple/object :relation :tuple/subject :attrs]))

(defn tuple-equivalent?
  [left right]
  (= (tuple-semantic-view left) (tuple-semantic-view right)))
