(ns zil.runtime.datascript
  "Draft DataScript runtime scaffold for Zil v0.1.

  This namespace intentionally stays small and explicit:
  - one connection creator,
  - tuple-fact and causal-edge transaction mappers,
  - snapshot extraction at a revision frontier,
  - causal order helpers via recursive Datalog rules."
  (:require [clojure.set :as cset]
            [clojure.string :as str]
            [datascript.core :as d]))

(def zil-schema
  "DataScript schema used by the draft runtime profile.

  Composite tuples enforce identity and simplify lookups:
  - :zil/fact-key = [object relation subject]
  - :zil/fact-at-rev = [object relation subject revision]
  - :zil/before-key = [left-event right-event]"
  {:zil/object {:db/index true}
   :zil/relation {:db/index true}
   :zil/subject {:db/index true}
   :zil/revision {:db/index true}
   :zil/event {:db/index true}
   :zil/op {:db/index true}
   :zil/fact-key {:db/tupleAttrs [:zil/object :zil/relation :zil/subject]
                    :db/unique :db.unique/identity}
   :zil/fact-at-rev {:db/tupleAttrs [:zil/object :zil/relation :zil/subject :zil/revision]
                       :db/unique :db.unique/identity}
   :zil/event-left {:db/index true}
   :zil/event-right {:db/index true}
   :zil/before-key {:db/tupleAttrs [:zil/event-left :zil/event-right]
                      :db/unique :db.unique/identity}})

(defn make-conn
  "Create a DataScript connection for Zil facts.
  Optional `extra-schema` may extend the base schema."
  ([] (make-conn {}))
  ([extra-schema]
   (d/create-conn (merge zil-schema extra-schema))))

(defn fact->tx
  "Convert a canonical Zil fact map into a DataScript transaction entity.

  Expected shape:
  {:object \"...\"
   :relation :keyword
   :subject \"...\"
   :attrs {...}        ; optional
   :revision 1
   :event :e1          ; optional but recommended
   :op :assert}        ; optional, defaults to :assert

  `:op :retract` provides snapshot-level retraction semantics."
  [{:keys [object relation subject attrs revision event op]
    :or {attrs {}
         op :assert
         revision 0}}]
  {:pre [(some? object)
         (keyword? relation)
         (some? subject)]}
  (cond-> {:zil/object object
           :zil/relation relation
           :zil/subject subject
           :zil/attrs attrs
           :zil/revision revision
           :zil/op op}
    event (assoc :zil/event event)))

(defn before-edge->tx
  "Convert a causal edge into a DataScript transaction entity.

  {:left :e1 :right :e2} means before(e1, e2)."
  [{:keys [left right]}]
  {:pre [(keyword? left) (keyword? right)]}
  {:zil/event-left left
   :zil/event-right right})

(defn transact-facts!
  "Transact one or more canonical fact maps."
  [conn facts]
  (d/transact! conn (mapv fact->tx facts)))

(defn transact-before-edges!
  "Transact one or more causal-edge maps."
  [conn edges]
  (d/transact! conn (mapv before-edge->tx edges)))

(defn rows-at-or-before
  "Internal row pull for all fact revisions <= `frontier`."
  [db frontier]
  (d/q '[:find ?o ?r ?s ?rev ?op ?attrs
         :in $ ?frontier
         :where
         [?e :zil/object ?o]
         [?e :zil/relation ?r]
         [?e :zil/subject ?s]
         [?e :zil/revision ?rev]
         [(<= ?rev ?frontier)]
         [?e :zil/op ?op]
         [?e :zil/attrs ?attrs]]
       db frontier))

(defn latest-fact-state
  "Pick the latest row by revision per logical fact key [object relation subject]."
  [rows]
  (reduce
   (fn [acc [o r s rev op attrs]]
     (let [k [o r s]
           prev (get acc k)]
       (if (or (nil? prev) (> rev (:revision prev)))
         (assoc acc k {:object o
                       :relation r
                       :subject s
                       :revision rev
                       :op op
                       :attrs attrs})
         acc)))
   {}
   rows))

(defn facts-at-or-before
  "Materialize snapshot semantics at frontier revision.

  Rule:
  1. consider all rows with revision <= frontier
  2. keep only the highest-revision row per logical key
  3. include it iff its :op is :assert"
  [db frontier]
  (->> (rows-at-or-before db frontier)
       latest-fact-state
       vals
       (filter #(= :assert (:op %)))
       (sort-by (juxt :object :relation :subject))
       vec))

(def before-rules
  "Recursive Datalog rules for transitive closure of before(e1, e2)."
  '[[(before* ?x ?y)
     [?e :zil/event-left ?x]
     [?e :zil/event-right ?y]]
    [(before* ?x ?y)
     [?e :zil/event-left ?x]
     [?e :zil/event-right ?z]
     (before* ?z ?y)]])

(defn before?
  "True when left-event causally precedes right-event."
  [db left-event right-event]
  (boolean
   (d/q '[:find ?x .
          :in $ % ?left ?right
          :where
          (before* ?left ?right)
          [(identity true) ?x]]
        db before-rules left-event right-event)))

(defn concurrent?
  "True when events are not ordered by happens-before in either direction."
  [db e1 e2]
  (and (not= e1 e2)
       (not (before? db e1 e2))
       (not (before? db e2 e1))))

(defn q
  "Pass-through query helper."
  [query db & inputs]
  (apply d/q query db inputs))

(defn- normalize-vc-counter
  [v]
  (cond
    (integer? v) (long v)
    (number? v) (long v)
    (string? v) (Long/parseLong (str/trim v))
    :else (throw (ex-info "Vector clock counter must be numeric"
                          {:value v}))))

(defn normalize-vector-clock
  "Normalize vector-clock maps into {actor-string -> long-counter}."
  [vc]
  (when-not (map? vc)
    (throw (ex-info "Vector clock must be a map" {:value vc})))
  (reduce-kv
   (fn [out k v]
     (let [actor (cond
                   (keyword? k) (name k)
                   (string? k) k
                   :else (str k))]
       (assoc out actor (normalize-vc-counter v))))
   {}
   vc))

(defn vector-clock-before?
  "True iff vc-left happens-before vc-right under vector-clock ordering."
  [vc-left vc-right]
  (let [l (normalize-vector-clock vc-left)
        r (normalize-vector-clock vc-right)
        actors (cset/union (set (keys l)) (set (keys r)))
        non-greater? (every? (fn [a] (<= (get l a 0) (get r a 0))) actors)
        strictly-smaller? (some (fn [a] (< (get l a 0) (get r a 0))) actors)]
    (and non-greater? (boolean strictly-smaller?))))

(defn vector-clock-concurrent?
  "True iff vector clocks are incomparable in either direction."
  [vc-a vc-b]
  (and (not (vector-clock-before? vc-a vc-b))
       (not (vector-clock-before? vc-b vc-a))))

(defn derive-before-edges-from-vector-clocks
  "Derive causal edges from event+vector-clock records.

  Input records shape:
  {:event :event_key
   :vector_clock {\"actorA\" 2 \"actorB\" 1}}"
  [events]
  (->> (for [{le :event lvc :vector_clock} events
             {re :event rvc :vector_clock} events
             :when (and (keyword? le)
                        (keyword? re)
                        (not= le re)
                        (vector-clock-before? lvc rvc))]
         {:left le :right re})
       distinct
       vec))

;; ---------------------------------------------------------------------------
;; ZIL → DataScript Datalog query translation
;; ---------------------------------------------------------------------------

(defn- zil-var? [t] (and (string? t) (str/starts-with? t "?")))

(defn- zil-term->ds
  "Map a ZIL object/subject term to a DataScript query term.
  Variable strings become Datalog symbols; literals pass through."
  [t]
  (if (zil-var? t) (symbol t) t))

(defn- literal->ds-clauses
  "Translate one positive ZIL literal to a sequence of DataScript where clauses.
  `eid-idx` is a unique integer used to name the generated entity variable."
  [{:keys [object relation subject attrs]} eid-idx]
  (let [e-sym     (symbol (str "?__e" eid-idx))
        obj       (zil-term->ds object)
        subj      (zil-term->ds subject)
        base      [[e-sym :zil/object obj]
                   [e-sym :zil/relation relation]
                   [e-sym :zil/subject subj]]
        attr-clauses
        (when (seq attrs)
          (let [a-sym (symbol (str "?__attrs" eid-idx))]
            (cons [e-sym :zil/attrs a-sym]
                  (mapcat (fn [[k v] ai]
                            (if (zil-var? v)
                              [[(list 'get a-sym k) (symbol v)]]
                              (let [tmp (symbol (str "?__atv" eid-idx "_" ai))]
                                [[(list 'get a-sym k) tmp]
                                 [(list '= tmp v)]])))
                          attrs
                          (range)))))]
    (vec (concat base attr-clauses))))

(defn- literal-zil-user-vars
  "Return the set of ZIL variable strings appearing in a literal's object, subject, attrs."
  [{:keys [object subject attrs]}]
  (into #{}
        (filter zil-var?
                (concat [object subject] (vals attrs)))))

(defn- neg-literal->ds-clause
  "Translate a negated ZIL literal to a DataScript (not-join ...) or (not ...) clause."
  [lit eid-idx bound-vars]
  (let [clauses   (literal->ds-clauses (dissoc lit :neg?) eid-idx)
        lit-vars  (literal-zil-user-vars lit)
        join-vars (->> lit-vars
                       (filter bound-vars)
                       (mapv symbol))]
    (if (seq join-vars)
      (apply list 'not-join join-vars clauses)
      (apply list 'not clauses))))

(defn query->ds-form
  "Translate a ZIL query IR map to a DataScript d/q compatible map.

  Positive literals are emitted as triple-pattern clauses.
  Negative literals become (not-join ...) clauses using the variables bound
  by the preceding positive literals."
  [{:keys [find where]}]
  (let [pos-lits  (remove :neg? where)
        neg-lits  (filter :neg? where)
        [pos-clauses bound-vars]
        (reduce (fn [[acc bound] [idx lit]]
                  (let [clauses (literal->ds-clauses lit idx)
                        new-bound (into bound (filter zil-var? (literal-zil-user-vars lit)))]
                    [(into acc clauses) new-bound]))
                [[] #{}]
                (map-indexed vector pos-lits))
        neg-clauses
        (map-indexed (fn [i lit]
                       (neg-literal->ds-clause lit (+ (count pos-lits) i) bound-vars))
                     neg-lits)]
    {:find  (mapv symbol find)
     :where (vec (concat pos-clauses neg-clauses))}))

(defn run-zil-query
  "Execute a ZIL query IR map against a DataScript DB.
  Returns {:vars [...] :rows [[...]]}."
  [db {:keys [find] :as query}]
  (let [ds-form (query->ds-form query)
        raw     (d/q ds-form db)
        rows    (->> raw (map vec) sort vec)]
    {:vars find :rows rows}))

(defn execute-queries-with-datascript
  "Transact `facts` into a fresh DataScript connection, then execute all ZIL
  `queries` against it.

  Returns {:conn <DataScript conn>
           :query-results {query-name {:vars [...] :rows [[...]]}}}"
  [facts queries]
  (let [conn (make-conn)
        _    (transact-facts! conn facts)
        db   (d/db conn)
        qr   (into {} (for [q queries]
                        [(:name q) (run-zil-query db q)]))]
    {:conn conn :query-results qr}))

;; ---------------------------------------------------------------------------
;; Native DataScript Datalog inference (ZIL rules → DataScript rule clauses)
;;
;; Instead of pre-materialising derived facts via the custom evaluator, positive
;; ZIL rules are compiled to DataScript Datalog rule clauses and DataScript's
;; own semi-naive engine does the inference at query time.
;;
;; Rules with NOT in their body cannot be compiled this way (DataScript Datalog
;; rules do not support negation).  Those rules must be pre-evaluated by the
;; custom evaluator; the resulting facts are added to the base set before calling
;; execute-with-native-datascript.
;; ---------------------------------------------------------------------------

(defn- rule-predicate-name
  "Derive the DataScript rule predicate symbol for a ZIL relation keyword."
  [relation]
  (symbol (str "zil:" (name relation))))

(defn- literal->ds-clauses-native
  "Like literal->ds-clauses but emits a rule-predicate call for relations in
  `derived-rels` that carry no attrs (attrs would not be representable in a
  two-argument rule head)."
  [{:keys [object relation subject attrs] :as lit} eid-idx derived-rels]
  (if (and (contains? derived-rels relation) (empty? attrs))
    [(list (rule-predicate-name relation)
           (zil-term->ds object)
           (zil-term->ds subject))]
    (literal->ds-clauses lit eid-idx)))

(defn compile-positive-rules->ds-rules
  "Compile positive ZIL rules (no NOT literals in body) to a DataScript rule
  vector suitable for the `%` input slot of d/q.

  Rules with any negated body literal are skipped — those strata must be handled
  by the custom evaluator.  Rules whose THEN atoms carry attrs are also skipped
  since a two-argument DataScript rule head cannot represent attrs.

  For multi-level derivation chains the compiled rules call each other via rule
  predicates, so DataScript's semi-naive Datalog engine handles transitivity."
  [rules]
  (let [pos-rules    (filter #(not-any? :neg? (:if %)) rules)
        derived-rels (into #{}
                           (mapcat (fn [r]
                                     (->> (:then r)
                                          (remove #(seq (:attrs %)))
                                          (map :relation)))
                                   pos-rules))]
    (->> pos-rules
         (mapcat
          (fn [{:keys [if then]}]
            (let [body-cls (apply concat
                                  (map-indexed
                                   (fn [i lit]
                                     (literal->ds-clauses-native lit i derived-rels))
                                   if))]
              (->> then
                   (remove #(seq (:attrs %)))
                   (mapv (fn [{:keys [object relation subject]}]
                           (let [head (list (rule-predicate-name relation)
                                            (zil-term->ds object)
                                            (zil-term->ds subject))]
                             (vec (cons head body-cls)))))))))
         vec)))

(defn query->ds-form-native
  "Like query->ds-form but uses rule-predicate calls for literals whose relation
  is in `derived-rels` and carry no attrs.  The emitted form includes :in '[$ %]
  so the DataScript rule set can be passed as the second input."
  [{:keys [find where]} derived-rels]
  (let [pos-lits (remove :neg? where)
        neg-lits (filter :neg? where)
        [pos-clauses bound-vars]
        (reduce (fn [[acc bound] [idx lit]]
                  (let [clauses   (literal->ds-clauses-native lit idx derived-rels)
                        new-bound (into bound (filter zil-var? (literal-zil-user-vars lit)))]
                    [(into acc clauses) new-bound]))
                [[] #{}]
                (map-indexed vector pos-lits))
        neg-clauses
        (map-indexed
         (fn [i lit]
           (let [bare      (dissoc lit :neg?)
                 clauses   (literal->ds-clauses-native bare (+ (count pos-lits) i) derived-rels)
                 lit-vars  (literal-zil-user-vars lit)
                 join-vars (->> lit-vars (filter bound-vars) (mapv symbol))]
             (if (seq join-vars)
               (apply list 'not-join join-vars clauses)
               (apply list 'not clauses))))
         neg-lits)]
    {:find  (mapv symbol find)
     :in    '[$ %]
     :where (vec (concat pos-clauses neg-clauses))}))

(defn run-zil-query-native
  "Run a ZIL query using DataScript's Datalog rule engine for inference.
  `db` should hold only base facts (not pre-materialised derived facts).
  `ds-rules` is from compile-positive-rules->ds-rules.
  `derived-rels` is the set of keyword relations defined by compiled rules."
  [db ds-rules derived-rels {:keys [find] :as query}]
  (let [ds-form (query->ds-form-native query derived-rels)
        raw     (d/q ds-form db ds-rules)
        rows    (->> raw (map vec) sort vec)]
    {:vars find :rows rows}))

(defn execute-with-native-datascript
  "Execute a ZIL model using DataScript's Datalog engine for rule inference.

  Positive rules (no NOT) are compiled to DataScript Datalog rule clauses.
  Rules with NOT are returned in :skipped-rules; their derived facts must already
  be included in `base-facts` by the caller (e.g. pre-evaluated by the custom
  evaluator up to the last negated stratum).

  Returns:
  {:conn          <DataScript conn with base facts>
   :query-results {query-name {:vars [...] :rows [...]}}
   :skipped-rules [names of rules with NOT — could not be compiled]
   :derived-rels  #{keyword ...}}"
  [base-facts rules queries]
  (let [pos-rules    (filter #(not-any? :neg? (:if %)) rules)
        neg-rules    (filter #(some :neg? (:if %)) rules)
        ds-rules     (compile-positive-rules->ds-rules pos-rules)
        derived-rels (into #{}
                           (mapcat (fn [r]
                                     (->> (:then r)
                                          (remove #(seq (:attrs %)))
                                          (map :relation)))
                                   pos-rules))
        conn         (make-conn)
        _            (transact-facts! conn base-facts)
        db           (d/db conn)
        qr           (into {} (for [q queries]
                                [(:name q)
                                 (run-zil-query-native db ds-rules derived-rels q)]))]
    {:conn          conn
     :query-results qr
     :skipped-rules (mapv :name neg-rules)
     :derived-rels  derived-rels}))
