(ns zil.profile.z3
  "SMT-backed checks for constraint profile declarations."
  (:require [clojure.java.shell :as sh]
            [clojure.string :as str]))

(defn z3-available?
  []
  (try
    (let [{:keys [exit out]} (sh/sh "z3" "-version")]
      (and (zero? exit)
           (re-find #"(?i)\bz3\b" (or out ""))))
    (catch Exception _
      false)))

(defn- read-while
  [s i pred]
  (let [n (count s)]
    (loop [j i]
      (if (and (< j n) (pred (.charAt s j)))
        (recur (inc j))
        j))))

(defn tokenize
  [s]
  (let [n (count s)
        two-char-ops {"&&" :and
                      "||" :or
                      "->" :implies
                      "=>" :implies
                      ">=" :>=
                      "<=" :<=
                      "==" :=
                      "!=" :!=}
        one-char-ops {\( :lparen
                      \) :rparen
                      \+ :+
                      \- :-
                      \* :*
                      \/ :/
                      \> :>
                      \< :<
                      \= :=
                      \! :not}]
    (loop [i 0
           out []]
      (if (>= i n)
        out
        (let [c (.charAt s i)]
          (cond
            (Character/isWhitespace c)
            (recur (inc i) out)

            (and (< (+ i 1) n)
                 (contains? two-char-ops (subs s i (+ i 2))))
            (let [raw (subs s i (+ i 2))
                  op (get two-char-ops raw)]
              (recur (+ i 2) (conj out {:type :op :value op :raw raw})))

            (contains? one-char-ops c)
            (let [op (get one-char-ops c)]
              (recur (inc i) (conj out {:type :op :value op :raw (str c)})))

            (Character/isDigit c)
            (let [j-int (read-while s i #(Character/isDigit %))
                  j (if (and (< j-int n)
                             (= (.charAt s j-int) \.)
                             (< (inc j-int) n)
                             (Character/isDigit (.charAt s (inc j-int))))
                      (read-while s (inc j-int) #(Character/isDigit %))
                      j-int)
                  raw (subs s i j)]
              (recur j (conj out {:type :number :raw raw})))

            (or (Character/isLetter c) (= c \_))
            (let [j (read-while s i #(or (Character/isLetterOrDigit %)
                                         (= % \_)
                                         (= % \:)
                                         (= % \.)
                                         (= % \-)))
                  raw (subs s i j)
                  low (str/lower-case raw)
                  tok (cond
                        (= low "true") {:type :bool :value true :raw raw}
                        (= low "false") {:type :bool :value false :raw raw}
                        (= low "and") {:type :op :value :and :raw raw}
                        (= low "or") {:type :op :value :or :raw raw}
                        (= low "not") {:type :op :value :not :raw raw}
                        (= low "implies") {:type :op :value :implies :raw raw}
                        :else {:type :ident :value raw :raw raw})]
              (recur j (conj out tok)))

            :else
            (throw (ex-info "Unsupported token in condition"
                            {:condition s
                             :index i
                             :char (str c)}))))))))

(defn- token-at
  [tokens i]
  (nth tokens i nil))

(declare parse-expr)

(defn- expect-op
  [tokens i op]
  (let [t (token-at tokens i)]
    (when-not (and t (= :op (:type t)) (= op (:value t)))
      (throw (ex-info "Expected operator while parsing condition"
                      {:expected op :token t :index i})))
    (inc i)))

(defn- parse-primary
  [tokens i]
  (let [t (token-at tokens i)]
    (when-not t
      (throw (ex-info "Unexpected end of condition expression" {:index i})))
    (cond
      (= :number (:type t))
      [{:kind :num :raw (:raw t)} (inc i)]

      (= :bool (:type t))
      [{:kind :bool :value (:value t)} (inc i)]

      (= :ident (:type t))
      [{:kind :var :name (:value t)} (inc i)]

      (and (= :op (:type t)) (= :lparen (:value t)))
      (let [[expr j] (parse-expr tokens (inc i))
            k (expect-op tokens j :rparen)]
        [expr k])

      :else
      (throw (ex-info "Unexpected token in condition expression"
                      {:token t :index i})))))

(declare parse-unary)

(defn- parse-unary
  [tokens i]
  (let [t (token-at tokens i)]
    (if (and (= :op (:type t))
             (contains? #{:not :-} (:value t)))
      (let [[node j] (parse-unary tokens (inc i))
            op (if (= :not (:value t)) :not :neg)]
        [{:kind :op :op op :args [node]} j])
      (parse-primary tokens i))))

(defn- parse-left-assoc
  [tokens i next-parser ops]
  (let [[left j] (next-parser tokens i)]
    (loop [lhs left
           idx j]
      (let [t (token-at tokens idx)]
        (if (and (= :op (:type t)) (contains? ops (:value t)))
          (let [[rhs idx*] (next-parser tokens (inc idx))]
            (recur {:kind :op :op (:value t) :args [lhs rhs]} idx*))
          [lhs idx])))))

(defn- parse-mul
  [tokens i]
  (parse-left-assoc tokens i parse-unary #{:* :/}))

(defn- parse-add
  [tokens i]
  (parse-left-assoc tokens i parse-mul #{:+ :-}))

(defn- parse-cmp
  [tokens i]
  (let [[left j] (parse-add tokens i)
        t (token-at tokens j)]
    (if (and (= :op (:type t))
             (contains? #{:> :>= :< :<= := :!=} (:value t)))
      (let [[right k] (parse-add tokens (inc j))]
        [{:kind :op :op (:value t) :args [left right]} k])
      [left j])))

(defn- parse-and
  [tokens i]
  (parse-left-assoc tokens i parse-cmp #{:and}))

(defn- parse-or
  [tokens i]
  (parse-left-assoc tokens i parse-and #{:or}))

(defn- parse-implies
  "Parse right-associative implication:
   a IMPLIES b IMPLIES c  ==  a IMPLIES (b IMPLIES c)."
  [tokens i]
  (let [[left j] (parse-or tokens i)
        t (token-at tokens j)]
    (if (and (= :op (:type t)) (= :implies (:value t)))
      (let [[right k] (parse-implies tokens (inc j))]
        [{:kind :op :op :implies :args [left right]} k])
      [left j])))

(defn parse-expr
  [tokens i]
  (parse-implies tokens i))

(defn parse-condition
  [condition]
  (let [tokens (tokenize condition)
        [expr i] (parse-expr tokens 0)]
    (when-not (= i (count tokens))
      (throw (ex-info "Trailing tokens in condition expression"
                      {:condition condition
                       :remaining (subvec (vec tokens) i)})))
    expr))

(defn- ensure-sort
  [env var-name expected]
  (let [actual (get env var-name)]
    (cond
      (nil? expected) env
      (nil? actual) (assoc env var-name expected)
      (= actual expected) env
      :else (throw (ex-info "Variable sort conflict in condition"
                            {:variable var-name
                             :actual actual
                             :expected expected})))))

(defn- expect-sort
  [actual expected context]
  (when (and expected actual (not= actual expected))
    (throw (ex-info "Sort mismatch in condition"
                    {:context context
                     :actual actual
                     :expected expected}))))

(declare infer-expr)

(defn- infer-binary-real
  [op args env expected]
  (let [[a b] args
        [_ env1] (infer-expr a env :Real)
        [_ env2] (infer-expr b env1 :Real)]
    (expect-sort :Real expected {:op op})
    [:Real env2]))

(defn- infer-binary-bool
  [op args env expected]
  (let [[a b] args
        [_ env1] (infer-expr a env :Bool)
        [_ env2] (infer-expr b env1 :Bool)]
    (expect-sort :Bool expected {:op op})
    [:Bool env2]))

(defn- infer-eq
  [op args env expected]
  (let [[a b] args
        [sa env1] (infer-expr a env nil)
        [sb env2] (infer-expr b env1 nil)
        target (or sa sb :Real)
        [sa* env3] (infer-expr a env2 target)
        [sb* env4] (infer-expr b env3 target)]
    (when (not= sa* sb*)
      (throw (ex-info "Equality compares values with incompatible sorts"
                      {:op op :left sa* :right sb*})))
    (expect-sort :Bool expected {:op op})
    [:Bool env4]))

(defn infer-expr
  [ast env expected]
  (case (:kind ast)
    :num
    (do
      (expect-sort :Real expected {:kind :num})
      [:Real env])

    :bool
    (do
      (expect-sort :Bool expected {:kind :bool})
      [:Bool env])

    :var
    (let [name (:name ast)
          env* (ensure-sort env name expected)
          actual (or expected (get env* name))]
      [actual env*])

    :op
    (let [op (:op ast)
          args (:args ast)]
      (case op
        :neg (let [[_ env1] (infer-expr (first args) env :Real)]
               (expect-sort :Real expected {:op op})
               [:Real env1])
        :not (let [[_ env1] (infer-expr (first args) env :Bool)]
               (expect-sort :Bool expected {:op op})
               [:Bool env1])
        :+ (infer-binary-real op args env expected)
        :- (infer-binary-real op args env expected)
        :* (infer-binary-real op args env expected)
        :/ (infer-binary-real op args env expected)
        :> (let [[_ env1] (infer-binary-real op args env nil)]
             (expect-sort :Bool expected {:op op})
             [:Bool env1])
        :>= (let [[_ env1] (infer-binary-real op args env nil)]
              (expect-sort :Bool expected {:op op})
              [:Bool env1])
        :< (let [[_ env1] (infer-binary-real op args env nil)]
             (expect-sort :Bool expected {:op op})
             [:Bool env1])
        :<= (let [[_ env1] (infer-binary-real op args env nil)]
              (expect-sort :Bool expected {:op op})
              [:Bool env1])
        := (infer-eq op args env expected)
        :!= (infer-eq op args env expected)
        :and (infer-binary-bool op args env expected)
        :or (infer-binary-bool op args env expected)
        :implies (infer-binary-bool op args env expected)
        (throw (ex-info "Unsupported condition operator for SMT"
                        {:op op}))))

    (throw (ex-info "Unknown AST node while inferring sorts"
                    {:ast ast}))))

(defn infer-sorts
  [asts]
  (reduce (fn [env ast]
            (let [[sort env*] (infer-expr ast env :Bool)]
              (when-not (= :Bool sort)
                (throw (ex-info "Condition must evaluate to Bool"
                                {:ast ast :sort sort})))
              env*))
          {}
          asts))

(defn- smt-sort
  [s]
  (case s
    :Bool "Bool"
    :Real "Real"
    (throw (ex-info "Unsupported SMT sort" {:sort s}))))

(defn- smt-symbol-table
  [names]
  (let [sorted (sort names)]
    (:mapping
     (reduce (fn [{:keys [used mapping] :as acc} nm]
               (let [base (-> nm
                              (str/replace #"[^A-Za-z0-9_]" "_")
                              (#(if (re-find #"^[0-9]" %) (str "v_" %) %))
                              (#(if (str/blank? %) "v" %)))
                     sym (loop [i 0]
                           (let [cand (if (zero? i) base (str base "_" i))]
                             (if (contains? used cand)
                               (recur (inc i))
                               cand)))]
                 {:used (conj used sym)
                  :mapping (assoc mapping nm sym)}))
             {:used #{} :mapping {}}
             sorted))))

(declare emit-expr)

(defn emit-expr
  [ast symbols]
  (case (:kind ast)
    :num (:raw ast)
    :bool (if (:value ast) "true" "false")
    :var (or (get symbols (:name ast))
             (throw (ex-info "Missing symbol for variable" {:name (:name ast)})))
    :op (let [op (:op ast)
              args (:args ast)
              e1 (emit-expr (first args) symbols)
              e2 (when-let [a2 (second args)] (emit-expr a2 symbols))]
          (case op
            :neg (str "(- " e1 ")")
            :not (str "(not " e1 ")")
            :+ (str "(+ " e1 " " e2 ")")
            :- (str "(- " e1 " " e2 ")")
            :* (str "(* " e1 " " e2 ")")
            :/ (str "(/ " e1 " " e2 ")")
            :> (str "(> " e1 " " e2 ")")
            :>= (str "(>= " e1 " " e2 ")")
            :< (str "(< " e1 " " e2 ")")
            :<= (str "(<= " e1 " " e2 ")")
            := (str "(= " e1 " " e2 ")")
            :!= (str "(not (= " e1 " " e2 "))")
            :and (str "(and " e1 " " e2 ")")
            :or (str "(or " e1 " " e2 ")")
            :implies (str "(=> " e1 " " e2 ")")
            (throw (ex-info "Unsupported operator while emitting SMT"
                            {:op op}))))
    (throw (ex-info "Unknown AST node while emitting SMT"
                    {:ast ast}))))

(defn compile-conditions
  ([conditions]
   (compile-conditions conditions {}))
  ([conditions {:keys [logic] :or {logic "ALL"}}]
   (let [logic-token (cond
                       (keyword? logic) (-> logic name str/upper-case)
                       (string? logic) (-> logic str/trim str/upper-case)
                       :else (str logic))
         _ (when-not (re-matches #"[A-Z0-9_+\-]+" logic-token)
             (throw (ex-info "Invalid SMT logic token"
                             {:logic logic
                              :normalized logic-token})))
         conds (->> conditions
                    (map #(str/trim (str %)))
                    (remove str/blank?)
                    vec)
         asts (mapv parse-condition conds)
         sorts (infer-sorts asts)
         symbols (smt-symbol-table (keys sorts))
         decls (->> sorts
                    (sort-by key)
                    (map (fn [[nm sort]]
                           (str "(declare-fun " (get symbols nm) " () " (smt-sort sort) ")"))))
         asserts (map (fn [ast]
                        (str "(assert " (emit-expr ast symbols) ")"))
                      asts)
         script (str
                 "(set-logic " logic-token ")\n"
                 (str/join "\n" decls)
                 (when (seq decls) "\n")
                 (str/join "\n" asserts)
                 (when (seq asserts) "\n")
                 "(check-sat)\n")]
     {:conditions conds
      :logic logic-token
      :asts asts
      :sorts sorts
      :symbols symbols
      :script script})))

(defn run-z3
  [script]
  (let [{:keys [out err exit]} (sh/sh "z3" "-in" :in script)
        status-token (->> (str/split-lines (or out ""))
                          (map str/trim)
                          (filter #{"sat" "unsat" "unknown"})
                          first)
        status (when status-token (keyword status-token))]
    (cond
      (not (zero? exit))
      {:ok false
       :status :error
       :exit exit
       :stderr err
       :stdout out}

      (nil? status)
      {:ok false
       :status :error
       :exit exit
       :stderr err
       :stdout out}

      :else
      {:ok (= status :sat)
       :status status
       :exit exit
       :stderr err
       :stdout out})))

(defn check-conditions
  ([conditions]
   (check-conditions conditions {}))
  ([conditions options]
   (if-not (z3-available?)
     {:ok false
      :status :unavailable
      :error "z3 executable not available in PATH"}
     (try
       (let [{:keys [script symbols sorts] :as compiled} (compile-conditions conditions options)
             solver (run-z3 script)]
         (merge compiled solver))
       (catch Exception e
         {:ok false
          :status :error
          :error (.getMessage e)
          :data (ex-data e)})))))

(defn check-policy-declarations
  [policies {:keys [scope] :or {scope :bundle}}]
  (let [valid (->> policies
                   (filter #(= :policy (:kind %)))
                   vec)
        missing-cond (for [{:keys [name attrs]} valid
                           :let [c (:condition attrs)]
                           :when (or (nil? c)
                                     (str/blank? (str c)))]
                       {:type :solver
                        :scope scope
                        :policy name
                        :status :error
                        :error "POLICY must define non-empty condition for SMT checks"})
        with-cond (for [{:keys [name attrs] :as decl} valid
                        :let [c (:condition attrs)]
                        :when (and c (not (str/blank? (str c))))]
                    (assoc decl :condition (str c)))]
    (if (empty? with-cond)
      {:ok (empty? missing-cond)
       :errors (vec missing-cond)
       :individual []
       :joint nil}
      (let [individual
            (for [{:keys [name condition]} with-cond]
              (let [r (check-conditions [condition])]
                {:policy name
                 :condition condition
                 :status (:status r)
                 :ok (:ok r)
                 :error (:error r)}))
            individual-errors
            (for [{:keys [policy status error]} individual
                  :when (not= status :sat)]
              {:type :solver
               :scope scope
               :policy policy
               :status status
               :error (or error
                          (str "Policy condition is not satisfiable: " status))})
            joint-check (check-conditions (mapv :condition with-cond))
            joint-error (when (not= :sat (:status joint-check))
                          {:type :solver
                           :scope scope
                           :status (:status joint-check)
                           :error (or (:error joint-check)
                                      (str "Joint policy set is not satisfiable: " (:status joint-check)))})
            all-errors (vec (concat missing-cond
                                    individual-errors
                                    (when joint-error [joint-error])))]
        {:ok (empty? all-errors)
         :errors all-errors
         :individual (vec individual)
         :joint {:status (:status joint-check)
                 :ok (:ok joint-check)
                 :error (:error joint-check)}}))))
