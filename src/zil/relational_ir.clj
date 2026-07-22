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

  `source` is optional provenance and must not affect semantic equality."
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
  "Remove provenance and frontend-only annotations for equivalence checks."
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
