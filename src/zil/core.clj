(ns zil.core
  "Core parser/evaluator for Zil v0.1.

  Supported surface syntax:
  - MODULE declarations
  - tuple facts: object#relation@subject [attrs].
  - rules with IF/THEN and AND/NOT conjunctions
  - queries with FIND ... WHERE ..."
  (:require [clojure.edn :as edn]
            [clojure.set :as cset]
            [clojure.string :as str]
            [zil.lower :as zl]
            [zil.runtime.datascript :as zr]))

(defn variable-token?
  "True when `x` is a query/rule variable (e.g. \"?x\")."
  [x]
  (and (string? x)
       (str/starts-with? x "?")
       (> (count x) 1)))

(defn parse-scalar
  "Parse scalar literals used in attrs:
  - quoted strings
  - booleans
  - ints / doubles
  - keywords / collections via safe EDN parse
  - fallback raw string token."
  [s]
  (let [t (str/trim s)]
    (cond
      (re-matches #"\"(?:\\.|[^\"])*\"" t) (edn/read-string t)
      (re-matches #"(?i)true|false" t) (Boolean/parseBoolean (str/lower-case t))
      (re-matches #"-?\d+" t) (Long/parseLong t)
      (re-matches #"-?\d+\.\d+" t) (Double/parseDouble t)
      (= "nil" t) nil
      (or (str/starts-with? t ":")
          (str/starts-with? t "[")
          (str/starts-with? t "{")
          (str/starts-with? t "(")
          (str/starts-with? t "#{"))
      (try
        (edn/read-string t)
        (catch Exception _
          t))
      :else t)))

(defn parse-term
  "Parse an object/subject/attr value token."
  [s]
  (parse-scalar (str/trim s)))

(defn split-top-level-comma
  "Split comma-separated text while respecting nested delimiters and quoted strings."
  [s context]
  (let [in (str/trim (or s ""))]
    (if (str/blank? in)
      []
      (let [final
            (loop [chs (seq in)
                   acc []
                   token ""
                   depth 0
                   in-string? false
                   escape? false]
              (if-let [c (first chs)]
                (cond
                  escape?
                  (recur (next chs) acc (str token c) depth in-string? false)

                  in-string?
                  (cond
                    (= c \\) (recur (next chs) acc (str token c) depth in-string? true)
                    (= c \") (recur (next chs) acc (str token c) depth false false)
                    :else (recur (next chs) acc (str token c) depth in-string? false))

                  (= c \")
                  (recur (next chs) acc (str token c) depth true false)

                  (#{\( \[ \{} c)
                  (recur (next chs) acc (str token c) (inc depth) in-string? false)

                  (#{\) \] \}} c)
                  (do
                    (when (zero? depth)
                      (throw (ex-info "Unbalanced closing delimiter"
                                      {:context context :text s})))
                    (recur (next chs) acc (str token c) (dec depth) in-string? false))

                  (and (= c \,) (zero? depth))
                  (recur (next chs) (conj acc (str/trim token)) "" depth in-string? false)

                  :else
                  (recur (next chs) acc (str token c) depth in-string? false))
                (do
                  (when in-string?
                    (throw (ex-info "Unterminated string literal"
                                    {:context context :text s})))
                  (when (not (zero? depth))
                    (throw (ex-info "Unbalanced delimiters"
                                    {:context context :text s})))
                  (conj acc (str/trim token)))))]
        (when (some str/blank? final)
          (throw (ex-info "Empty entry in comma-separated list"
                          {:context context :text s})))
        final))))

(defn parse-attrs
  "Parse attrs payload from inside `[...]`."
  [attrs-str]
  (if (or (nil? attrs-str) (str/blank? attrs-str))
    {}
    (reduce
     (fn [out token]
       (let [[_ k raw-v] (or (re-matches #"\s*([A-Za-z0-9_:\-\.]+)\s*=\s*(.+?)\s*$" token)
                             (throw (ex-info "Invalid attr entry, expected key=value"
                                             {:entry token :attrs attrs-str})))]
         (assoc out (keyword k) (parse-term raw-v))))
     {}
     (split-top-level-comma attrs-str "attrs"))))

(def atom-re
  #"^\s*(.+?)#([A-Za-z0-9_:\-\.]+)@(.+?)(?:\s*\[(.*)\])?\s*$")

(defn trim-trailing-dot
  [s]
  (-> s str/trim (str/replace #"\.\s*$" "")))

(defn parse-atom
  "Parse one tuple atom (without NOT)."
  [s]
  (let [raw (trim-trailing-dot s)]
    (when-not (str/includes? raw "#")
      (throw (ex-info "Invalid atom: missing `#` separator" {:text s})))
    (when-not (str/includes? raw "@")
      (throw (ex-info "Invalid atom: missing `@` separator" {:text s})))
    (let [[_ object relation subject attrs] (or (re-matches atom-re raw)
                                                (throw (ex-info "Invalid atom syntax" {:text s})))]
      {:object (parse-term object)
       :relation (keyword (str/trim relation))
       :subject (parse-term subject)
       :attrs (parse-attrs attrs)})))

(defn split-and
  "Split a rule/query body on AND conjunctions, respecting double-quoted strings."
  [s]
  (let [;; Tokenise: run a char-by-char scan tracking in-quotes state.
        ;; Emit a split marker wherever we see whitespace+AND+whitespace outside quotes.
        chars (seq s)
        sentinel "\u0000"
        result (loop [remaining chars
                      in-quote? false
                      buf (StringBuilder.)]
                 (if (empty? remaining)
                   (.toString buf)
                   (let [c (first remaining)
                         rest* (rest remaining)]
                     (cond
                       ;; Toggle quote state on unescaped "
                       (and (= c \") (not (and (seq (.toString buf))
                                               (= (last (.toString buf)) \\))))
                       (do (.append buf c)
                           (recur rest* (not in-quote?) buf))
                       ;; When NOT in a quote, check for AND pattern
                       (and (not in-quote?) (= c \space))
                       (let [remaining-str (apply str remaining)]
                         (if-let [match (re-find #"(?i)^\s+AND\s+" remaining-str)]
                           (do (.append buf sentinel)
                               (recur (drop (dec (count match)) rest*) false buf))
                           (do (.append buf c)
                               (recur rest* false buf))))
                       :else
                       (do (.append buf c)
                           (recur rest* in-quote? buf))))))]
    (->> (str/split result (re-pattern sentinel))
         (map str/trim)
         (remove str/blank?)
         vec)))

(defn parse-literal
  "Parse body literal; supports optional `NOT` prefix."
  [s]
  (let [t (str/trim s)
        neg? (boolean (re-find #"(?i)^NOT\s+" t))
        atom-s (if neg?
                 (str/replace-first t #"(?i)^NOT\s+" "")
                 t)]
    (assoc (parse-atom atom-s) :neg? neg?)))

(defn parse-rule-body
  [s]
  (->> (split-and s)
       (mapv parse-literal)))

(defn parse-rule-head
  [s]
  (->> (split-and s)
       (mapv parse-atom)))

(defn parse-find-line
  [line]
  (let [[_ vars where] (or (re-matches #"(?i)^FIND\s+(.+?)\s+WHERE\s+(.+)\.\s*$" (str/trim line))
                           (throw (ex-info "Invalid QUERY FIND syntax" {:line line})))
        find-vars (->> (str/split (str/trim vars) #"\s+")
                       (mapv str/trim))]
    {:find find-vars
     :where (parse-rule-body where)}))

(defn preprocess-lines
  "Remove line comments and blank lines."
  [text]
  (letfn [(strip-line-comment [line]
            (loop [chs (seq line)
                   out ""
                   in-string? false
                   escape? false]
              (if-let [c (first chs)]
                (cond
                  escape?
                  (recur (next chs) (str out c) in-string? false)

                  in-string?
                  (cond
                    (= c \\) (recur (next chs) (str out c) in-string? true)
                    (= c \") (recur (next chs) (str out c) false false)
                    :else (recur (next chs) (str out c) in-string? false))

                  (= c \")
                  (recur (next chs) (str out c) true false)

                  (and (= c \/) (= (first (next chs)) \/))
                  out

                  :else
                  (recur (next chs) (str out c) false false))
                out)))]
    (->> (str/split-lines text)
         (map strip-line-comment)
         (map str/trim)
         (remove str/blank?)
         vec)))

(def macro-header-re
  #"(?i)^MACRO\s+([A-Za-z0-9_.:-]+)\s*\((.*)\)\s*:\s*$")

(def macro-end-re
  #"(?i)^ENDMACRO\.\s*$")

(def macro-emit-re
  #"(?i)^EMIT\s+(.+)$")

(def macro-use-re
  #"(?i)^USE\s+([A-Za-z0-9_.:-]+)\s*\((.*)\)\.\s*$")

(defn split-arguments
  "Split a comma-separated argument list, respecting quoted strings and bracket depth."
  [s]
  (split-top-level-comma s "macro arguments"))

(def stdlib-declaration-re
  #"(?i)^(SERVICE|HOST|DATASOURCE|METRIC|POLICY|EVENT|PROVIDER|TM_ATOM|LTS_ATOM|REFINES|CORRESPONDS|PROOF_OBLIGATION|FORMALIZATION_TARGET|LANGUAGE_PROFILE|GRAMMAR_PROFILE|PARSER_ADAPTER|DSL_PROFILE|QUERY_PACK)\s+([A-Za-z0-9_.:-]+)(?:\s*\[(.*)\])?\.\s*$")

(defn parse-stdlib-declaration
  "Parse one standard-library declaration line.
  Example:
  SERVICE payment [env=prod, criticality=high]."
  [line]
  (when-let [[_ kind name attrs] (re-matches stdlib-declaration-re line)]
    {:kind (keyword (str/lower-case kind))
     :name name
     :attrs (parse-attrs attrs)}))

(defn parse-macro-params
  [s]
  (let [params (split-arguments s)]
    (doseq [p params]
      (when-not (re-matches #"[A-Za-z_][A-Za-z0-9_:\-\.]*" p)
        (throw (ex-info "Invalid macro parameter name" {:param p}))))
    (when (not= (count params) (count (distinct params)))
      (throw (ex-info "Duplicate macro parameter name" {:params params})))
    (vec params)))

(defn collect-macro-definitions
  "Collect `MACRO ... ENDMACRO.` definitions and return:
  {:macros {name {:params [...] :emit [...]}} :payload [...non-definition lines...]}"
  [lines]
  (let [n (count lines)]
    (loop [i 0
           macros {}
           payload []]
      (if (>= i n)
        {:macros macros :payload payload}
        (let [line (nth lines i)]
          (if-let [[_ name params-s] (re-matches macro-header-re line)]
            (let [params (parse-macro-params params-s)
                  _ (when (contains? macros name)
                      (throw (ex-info "Duplicate macro definition" {:macro name})))
                  [next-i emit-lines]
                  (loop [j (inc i)
                         emit-lines []]
                    (when (>= j n)
                      (throw (ex-info "Unterminated macro definition; missing ENDMACRO." {:macro name})))
                    (let [body-line (nth lines j)]
                      (cond
                        (re-matches macro-end-re body-line)
                        [(inc j) emit-lines]

                        :else
                        (if-let [[_ emit] (re-matches macro-emit-re body-line)]
                          (recur (inc j) (conj emit-lines emit))
                          (throw (ex-info "Invalid macro body line (expected EMIT or ENDMACRO.)"
                                          {:macro name :line body-line}))))))]
              (recur next-i
                     (assoc macros name {:params params :emit emit-lines})
                     payload))
            (recur (inc i) macros (conj payload line))))))))

(defn instantiate-macro
  [macros name args-s]
  (let [{:keys [params emit] :as m} (get macros name)]
    (when-not m
      (throw (ex-info "Unknown macro invocation" {:macro name})))
    (let [args (split-arguments args-s)]
      (when (not= (count args) (count params))
        (throw (ex-info "Macro arity mismatch"
                        {:macro name :expected (count params) :actual (count args)})))
      (let [sub-map (zipmap params args)]
        (mapv (fn [line]
                (reduce-kv (fn [acc p v]
                             (str/replace acc (str "{{" p "}}") v))
                           line
                           sub-map))
              emit)))))

(defn expand-macro-uses
  "Expand `USE macro(args...).` lines, recursively."
  [lines macros]
  (loop [queue (seq lines)
         out []
         steps 0]
    (if-let [line (first queue)]
      (if-let [[_ macro-name args-s] (re-matches macro-use-re line)]
        (let [next-steps (inc steps)]
          (when (> next-steps 10000)
            (throw (ex-info "Macro expansion exceeded safe step limit (possible recursion loop)"
                            {:steps next-steps})))
          (let [expanded (instantiate-macro macros macro-name args-s)]
            (recur (concat expanded (rest queue)) out next-steps)))
        (recur (next queue) (conj out line) steps))
      (vec out))))

(defn expand-macros
  "Expand native Zil macros. This is a language-level feature and does not use Clojure macros.

  Macro syntax:
  - `MACRO name(p1, p2):`
  - body lines: `EMIT ...`
  - end: `ENDMACRO.`
  - invocation: `USE name(arg1, arg2).`
  - placeholders in EMIT lines: `{{p1}}`."
  [text]
  (let [lines (preprocess-lines text)
        {:keys [macros payload]} (collect-macro-definitions lines)]
    (expand-macro-uses payload macros)))

(defn parse-program
  "Parse Zil source text into canonical structural IR."
  [text]
  (let [lines (expand-macros text)
        n (count lines)]
    (loop [i 0
           out {:module nil :facts [] :rules [] :queries [] :declarations []}]
      (if (>= i n)
        out
        (let [line (nth lines i)
              decl (parse-stdlib-declaration line)]
          (cond
            (re-matches #"(?i)^MODULE\s+[A-Za-z0-9_.:-]+\.\s*$" line)
            (let [[_ mod] (re-matches #"(?i)^MODULE\s+([A-Za-z0-9_.:-]+)\.\s*$" line)]
              (recur (inc i) (assoc out :module mod)))

            (re-matches #"(?i)^RULE\s+[A-Za-z0-9_.:-]+\s*:\s*$" line)
            (let [[_ name] (re-matches #"(?i)^RULE\s+([A-Za-z0-9_.:-]+)\s*:\s*$" line)
                  if-line (or (get lines (inc i))
                              (throw (ex-info "RULE missing IF line" {:rule name})))
                  then-line (or (get lines (+ i 2))
                                (throw (ex-info "RULE missing THEN line" {:rule name})))
                  _ (when-not (re-matches #"(?i)^IF\s+.+$" if-line)
                      (throw (ex-info "RULE IF line has invalid syntax" {:rule name :line if-line})))
                  _ (when-not (re-matches #"(?i)^THEN\s+.+\.\s*$" then-line)
                      (throw (ex-info "RULE THEN line has invalid syntax" {:rule name :line then-line})))
                  if-body (str/replace-first if-line #"(?i)^IF\s+" "")
                  then-body (str/replace-first then-line #"(?i)^THEN\s+" "")
                  rule {:name name
                        :if (parse-rule-body if-body)
                        :then (parse-rule-head then-body)}]
              (recur (+ i 3) (update out :rules conj rule)))

            (re-matches #"(?i)^QUERY\s+[A-Za-z0-9_.:-]+\s*:\s*$" line)
            (let [[_ name] (re-matches #"(?i)^QUERY\s+([A-Za-z0-9_.:-]+)\s*:\s*$" line)
                  [find-line next-i]
                  (loop [j (inc i) acc []]
                    (let [l (or (get lines j)
                                (throw (ex-info "QUERY missing FIND line" {:query name})))
                          acc (conj acc l)]
                      (if (re-matches #".*\.\s*$" l)
                        [(str/join " " acc) (inc j)]
                        (recur (inc j) acc))))
                  q (assoc (parse-find-line find-line) :name name)]
              (recur next-i (update out :queries conj q)))

            decl
            (let [lowered (zl/declaration->facts decl)]
              (recur (inc i)
                     (-> out
                         (update :declarations conj decl)
                         (update :facts into lowered))))

            (re-matches #".+\.\s*$" line)
            (recur (inc i) (update out :facts conj (parse-atom line)))

            :else
            (throw (ex-info "Unrecognized line while parsing program" {:line line :index i}))))))))

(defn literal-vars
  [{:keys [object subject attrs]}]
  (into #{}
        (concat (when (variable-token? object) [object])
                (when (variable-token? subject) [subject])
                (for [[_ v] attrs :when (variable-token? v)] v))))

(defn- ensure-rule-safety!
  [{:keys [name if then]}]
  (let [pos-lits (filterv (complement :neg?) if)
        neg-lits (filterv :neg? if)
        pos-vars (into #{} (mapcat literal-vars) pos-lits)
        neg-vars (into #{} (mapcat literal-vars) neg-lits)
        head-vars (into #{} (mapcat literal-vars) then)]
    (when (not (cset/subset? neg-vars pos-vars))
      (throw (ex-info "Unsafe negation: NOT literal uses unbound variables"
                      {:rule name :negative-vars neg-vars :positive-vars pos-vars})))
    (when (not (cset/subset? head-vars pos-vars))
      (throw (ex-info "Rule head contains variables not bound in positive body"
                      {:rule name :head-vars head-vars :positive-vars pos-vars})))))

(defn- rule-relations
  [{:keys [if then]}]
  {:head (into #{} (map :relation) then)
   :pos (into #{} (map :relation) (remove :neg? if))
   :neg (into #{} (map :relation) (filter :neg? if))})

(defn- relax-strata
  [strata edges]
  (reduce
   (fn [m [from to w]]
     (let [cand (+ (get m from 0) w)]
       (if (> cand (get m to 0))
         (assoc m to cand)
         m)))
   strata
   edges))

(defn stratify-rules
  "Compute stratum index per relation.
  Throws when rules are not stratifiable."
  [rules]
  (let [rels (into #{}
                   (mapcat (fn [r]
                             (let [{:keys [head pos neg]} (rule-relations r)]
                               (concat head pos neg)))
                           rules))
        base (zipmap rels (repeat 0))
        edges (mapcat (fn [r]
                        (let [{:keys [head pos neg]} (rule-relations r)]
                          (concat
                           (for [h head, p pos] [p h 0])
                           (for [h head, n neg] [n h 1]))))
                      rules)
        n (count rels)
        sN (nth (iterate #(relax-strata % edges) base) (max 1 n))
        sN1 (relax-strata sN edges)]
    (when (not= sN sN1)
      (throw (ex-info "Program is not stratifiable (negative cycle detected)" {})))
    sN))

(defn compile-program
  "Parse + validate + stratify a Zil program.
  opts: {:skip-stratify? true} — skip stratification check (for external engines like Souffle)."
  ([text] (compile-program text {}))
  ([text {:keys [skip-stratify?]}]
   (let [{:keys [module facts rules queries declarations] :as parsed} (parse-program text)]
     (when (str/blank? module)
       (throw (ex-info "Program must define MODULE <name>." {})))
     (zl/validate-declarations! declarations)
     (when-not skip-stratify?
       (doseq [r rules] (ensure-rule-safety! r)))
     (let [strata (if skip-stratify?
                    (zipmap (map :relation (mapcat :then rules)) (repeat 0))
                    (stratify-rules rules))
           rules* (mapv (fn [r]
                          (let [{:keys [head]} (rule-relations r)
                                body (vec (concat (remove :neg? (:if r))
                                                  (filter :neg? (:if r))))]
                            (assoc r
                                   :if body
                                   :stratum (apply max 0 (map #(get strata % 0) head)))))
                        rules)]
       (assoc parsed
              :rules rules*
              :strata strata
              :queries queries
              :facts facts
              :declarations declarations)))))

(defn- bind-var
  [env var val]
  (if (contains? env var)
    (when (= (get env var) val) env)
    (assoc env var val)))

(defn- match-term
  [env pattern value]
  (if (variable-token? pattern)
    (bind-var env pattern value)
    (when (= pattern value) env)))

(defn- match-attrs
  [env pat-attrs fact-attrs]
  (reduce-kv
   (fn [acc k v]
     (when acc
       (when (contains? fact-attrs k)
         (match-term acc v (get fact-attrs k)))))
   env
   pat-attrs))

(defn- match-positive
  [facts-by-rel literal env]
  (let [candidates (get facts-by-rel (:relation literal) [])]
    (for [fact candidates
          :let [e1 (match-term env (:object literal) (:object fact))]
          :when e1
          :let [e2 (match-term e1 (:subject literal) (:subject fact))]
          :when e2
          :let [e3 (match-attrs e2 (:attrs literal) (:attrs fact))]
          :when e3]
      e3)))

(defn- has-match?
  [facts-by-rel literal env]
  (boolean (seq (match-positive facts-by-rel literal env))))

(declare plan-body-literals)

(defn- eval-body
  [pos-facts-by-rel neg-facts-by-rel body planner-hint]
  (let [lits* (plan-body-literals pos-facts-by-rel body planner-hint)]
    (loop [envs [{}]
           lits lits*]
    (if (empty? lits)
      envs
      (let [{:keys [neg?] :as lit} (first lits)
            next-envs (if neg?
                        (filterv #(not (has-match? neg-facts-by-rel (dissoc lit :neg?) %))
                                 envs)
                        (vec (mapcat #(match-positive pos-facts-by-rel lit %) envs)))]
          (recur next-envs (rest lits)))))))

(defn- ground-term
  [env t]
  (if (variable-token? t)
    (or (get env t)
        (throw (ex-info "Unbound variable while grounding fact" {:var t :env env})))
    t))

(defn- ground-fact
  [env {:keys [object relation subject attrs]}]
  {:object (ground-term env object)
   :relation relation
   :subject (ground-term env subject)
   :attrs (reduce-kv (fn [m k v] (assoc m k (ground-term env v))) {} attrs)})

(defn- facts->index
  [facts]
  (group-by :relation facts))

(defn- token->name
  [v]
  (cond
    (string? v) v
    (keyword? v) (name v)
    (symbol? v) (name v)
    :else (str v)))

(defn- attr-values
  [v]
  (if (and (coll? v) (not (map? v)))
    v
    [v]))

(def ^:private default-planner-hint :high_selectivity_first)

(defn- planner-hint-token
  [v]
  (keyword (str/lower-case (token->name v))))

(defn planner-hint-from-declarations
  "Resolve planner hint from DSL_PROFILE declarations.
  If no explicit hint is present, fallback to `default-planner-hint`."
  [declarations]
  (let [hints (->> declarations
                   (filter #(= :dsl_profile (:kind %)))
                   (map #(get-in % [:attrs :planner_hint]))
                   (remove nil?)
                   (map planner-hint-token)
                   vec)]
    (or (first hints) default-planner-hint)))

(defn- literal-variables
  [lit]
  (literal-vars lit))

(defn- literal-constant-count
  [{:keys [object subject attrs]}]
  (let [base (+ (if (variable-token? object) 0 1)
                (if (variable-token? subject) 0 1))
        attr-constants (count (remove variable-token? (vals attrs)))]
    (+ base attr-constants)))

(defn- relation-cardinality
  [facts-by-rel rel]
  (count (get facts-by-rel rel [])))

(defn- choose-best-literal
  [remaining bound-vars facts-by-rel planner-hint]
  (let [scored
        (map-indexed
         (fn [idx lit]
           (let [lit-vars (literal-variables lit)
                 bound-count (count (filter bound-vars lit-vars))
                 const-count (literal-constant-count lit)
                 rel-size (relation-cardinality facts-by-rel (:relation lit))
                 score (case planner-hint
                         :bound_first [(- bound-count) rel-size (- const-count) idx]
                         :high_selectivity_first [rel-size (- bound-count) (- const-count) idx]
                         ;; fallback keeps deterministic behavior close to source order
                         [idx])]
             {:idx idx
              :lit lit
              :score score}))
         remaining)]
    (first (sort-by :score scored))))

(defn- plan-positive-literals
  [facts-by-rel positives planner-hint]
  (if (or (= planner-hint :as_is)
          (<= (count positives) 1))
    positives
    (loop [remaining (vec positives)
           bound-vars #{}
           out []]
      (if (empty? remaining)
        out
        (let [{:keys [idx lit]} (choose-best-literal remaining bound-vars facts-by-rel planner-hint)
              lit-vars (set (literal-variables lit))
              next-remaining (vec (concat (subvec remaining 0 idx)
                                          (subvec remaining (inc idx))))]
          (recur next-remaining
                 (into bound-vars lit-vars)
                 (conj out lit)))))))

(defn plan-body-literals
  "Return planned body literal order.

  Positive literals are reordered according to planner hint.
  Negative literals stay at the end to preserve stratified-negation execution shape."
  [facts-by-rel body planner-hint]
  (let [positives (vec (remove :neg? body))
        negatives (vec (filter :neg? body))
        planned-pos (plan-positive-literals facts-by-rel positives planner-hint)]
    (vec (concat planned-pos negatives))))

(defn- apply-rule
  [rule pos-index neg-index planner-hint]
  (let [envs (eval-body pos-index neg-index (:if rule) planner-hint)]
    (into #{}
          (mapcat (fn [env] (map #(ground-fact env %) (:then rule))) envs))))

(defn- eval-stratum
  [base-facts rules planner-hint]
  (loop [current (set base-facts)]
    (let [pos-index (facts->index current)
          neg-index (facts->index base-facts)
          derived (into #{}
                        (mapcat #(apply-rule % pos-index neg-index planner-hint) rules))
          new-facts (cset/difference derived current)]
      (if (empty? new-facts)
        (cset/difference current (set base-facts))
        (recur (into current new-facts))))))

(defn run-query
  "Evaluate one query against a fact set.
  Returns {:vars [...] :rows [[...]]}."
  [facts {:keys [find where]} planner-hint]
  (let [index (facts->index facts)
        where* (plan-body-literals index where planner-hint)
        envs (eval-body index index where* planner-hint)
        rows (->> envs
                  (mapv (fn [env] (mapv #(get env %) find)))
                  distinct
                  vec)]
    {:vars find :rows rows}))

(defn- canonical-ns-ref
  [prefix v]
  (let [raw (-> v token->name str/trim)
        pfx (str (name prefix) ":")]
    (if (str/starts-with? raw pfx)
      (subs raw (count pfx))
      raw)))

(defn- parse-query-pack
  [{:keys [name attrs]}]
  (let [queries (->> (attr-values (:queries attrs))
                     (map token->name)
                     (map str/trim)
                     (remove str/blank?)
                     vec)
        must-return (->> (if (contains? attrs :must_return)
                           (attr-values (:must_return attrs))
                           [])
                         (map token->name)
                         (map str/trim)
                         (remove str/blank?)
                         vec)
        canonical (canonical-ns-ref :query_pack name)]
    {:name canonical
     :source_name name
     :queries queries
     :must_return must-return}))

(defn- parse-dsl-profile
  [{:keys [name attrs]}]
  (let [query-packs (->> (attr-values (:query_pack attrs))
                         (map #(canonical-ns-ref :query_pack %))
                         (remove str/blank?)
                         vec)
        canonical (canonical-ns-ref :dsl_profile name)]
    {:name canonical
     :source_name name
     :query_packs query-packs}))

(defn- select-dsl-profiles
  [profiles profile-name]
  (if (some? profile-name)
    (let [wanted (canonical-ns-ref :dsl_profile profile-name)
          selected (filterv #(= wanted (:name %)) profiles)]
      (when (empty? selected)
        (throw (ex-info "Requested DSL profile not found"
                        {:profile profile-name
                         :available (mapv :name profiles)})))
      selected)
    profiles))

(defn- query-ci-selection
  [{:keys [queries declarations]} profile-name]
  (let [query-defs (mapv :name queries)
        query-def-set (set query-defs)
        packs (->> declarations
                   (filter #(= :query_pack (:kind %)))
                   (map parse-query-pack)
                   vec)
        pack-index (into {}
                         (map (fn [p] [(:name p) p]))
                         packs)
        profiles (->> declarations
                      (filter #(= :dsl_profile (:kind %)))
                      (map parse-dsl-profile)
                      vec)
        selected-profiles (select-dsl-profiles profiles profile-name)
        selected-pack-names (if (seq selected-profiles)
                              (->> selected-profiles
                                   (mapcat :query_packs)
                                   distinct
                                   vec)
                              [])
        selected-packs (->> selected-pack-names
                            (map #(get pack-index %))
                            (remove nil?)
                            vec)
        missing-packs (->> selected-pack-names
                           (filter #(nil? (get pack-index %)))
                           vec)
        selected-queries (if (seq selected-packs)
                           (->> selected-packs
                                (mapcat :queries)
                                distinct
                                vec)
                           query-defs)
        selected-query-set (set selected-queries)
        missing-query-defs (->> selected-queries
                                (filter #(not (contains? query-def-set %)))
                                vec)
        must-return (->> selected-packs
                         (mapcat :must_return)
                         distinct
                         vec)
        active-query-set (cset/difference selected-query-set (set missing-query-defs))]
    {:profiles profiles
     :selected_profiles selected-profiles
     :packs packs
     :selected_packs selected-packs
     :missing_packs missing-packs
     :query_defs query-defs
     :selected_queries selected-queries
     :active_query_set active-query-set
     :missing_query_defs missing-query-defs
     :must_return must-return}))

(defn execute-compiled
  "Execute compiled program and return final facts + query results."
  ([compiled]
   (execute-compiled compiled {}))
  ([{:keys [module facts rules queries declarations]}
    {:keys [query-names]}]
   (let [planner-hint (planner-hint-from-declarations declarations)
         strata (sort (distinct (map :stratum rules)))
         by-stratum (group-by :stratum rules)
         final-facts (reduce
                      (fn [acc s]
                        (let [derived (eval-stratum acc (get by-stratum s []) planner-hint)]
                          (into acc derived)))
                      (set facts)
                      strata)
         selected-query-set (some->> query-names (into #{}))
         selected-queries (if (seq selected-query-set)
                            (filterv #(contains? selected-query-set (:name %)) queries)
                            queries)
         missing-query-names (if (seq selected-query-set)
                               (->> selected-query-set
                                    (remove (set (map :name queries)))
                                    sort
                                    vec)
                               [])
         {:keys [conn query-results]}
         (zr/execute-queries-with-datascript (vec final-facts) selected-queries)]
     {:module module
      :facts (->> final-facts
                  (sort-by (juxt :object :relation :subject))
                  vec)
      :planner_hint planner-hint
      :declarations declarations
      :selected_query_names (mapv :name selected-queries)
      :missing_query_names missing-query-names
      :conn conn
      :queries query-results})))

(defn query-plan-compiled
  "Build a planner report (without evaluating rules to fixpoint)."
  [{:keys [module facts queries declarations]}]
  (let [planner-hint (planner-hint-from-declarations declarations)
        idx (facts->index facts)
        relation-cardinality (->> idx
                                  (map (fn [[rel rows]]
                                         [rel (count rows)]))
                                  (sort-by (comp name first))
                                  vec)
        active-dsl-profiles (->> declarations
                                 (filter #(= :dsl_profile (:kind %)))
                                 (map :name)
                                 sort
                                 vec)
        planned-queries
        (mapv
         (fn [{:keys [name find where]}]
           (let [planned-where (plan-body-literals idx where planner-hint)]
             {:name name
              :find find
              :original_relations (mapv :relation where)
              :planned_relations (mapv :relation planned-where)
              :where_original where
              :where_planned planned-where}))
         queries)]
    {:ok true
     :module module
     :planner_hint planner-hint
     :active_dsl_profiles active-dsl-profiles
     :relation_cardinality relation-cardinality
     :queries planned-queries}))

(defn query-plan-program
  "Parse + compile + return adaptive query plan report for ZIL source text."
  [text]
  (-> text
      compile-program
      query-plan-compiled))

(defn query-plan-file
  "Read source file and return adaptive query plan report."
  [path]
  (query-plan-program (slurp path)))

(defn query-ci-compiled
  "Run DSL-aware query CI checks over a compiled program.

  Options:
  - :profile optional DSL_PROFILE name. If omitted, all DSL profiles are active.
  - :include_rows include full query rows in report (default: true)."
  ([compiled]
   (query-ci-compiled compiled {}))
  ([compiled {:keys [profile include_rows]
              :or {include_rows true}}]
   (let [{:keys [module declarations]}
         compiled
         planner-hint (planner-hint-from-declarations declarations)
         {:keys [profiles selected_profiles selected_packs missing_packs
                 query_defs selected_queries active_query_set missing_query_defs must_return]}
         (query-ci-selection compiled profile)
         exec (execute-compiled compiled {:query-names active_query_set})
         must-return-checks
         (mapv
          (fn [query-name]
            (let [rows (get-in exec [:queries query-name :rows] [])
                  row-count (count rows)]
              {:query query-name
               :row_count row-count
               :ok (pos? row-count)}))
          must_return)
         failed-must-return (->> must-return-checks
                                 (remove :ok)
                                 (mapv :query))
         must-return-set (set must_return)
         query-summary
         (->> (keys (:queries exec))
              sort
              (mapv (fn [qname]
                      {:query qname
                       :row_count (count (get-in exec [:queries qname :rows] []))
                       :must_return (contains? must-return-set qname)})))
         ok? (and (empty? missing_packs)
                  (empty? missing_query_defs)
                  (empty? failed-must-return))]
     {:ok ok?
      :module module
      :planner_hint planner-hint
      :requested_profile (when profile (canonical-ns-ref :dsl_profile profile))
      :active_dsl_profiles (mapv :name profiles)
      :selected_dsl_profiles (mapv :name selected_profiles)
      :selected_query_packs (mapv :name selected_packs)
      :query_defs query_defs
      :selected_queries selected_queries
      :query_summary query-summary
      :checks {:missing_query_packs missing_packs
               :missing_query_defs missing_query_defs
               :must_return must-return-checks
               :failed_must_return failed-must-return}
      :queries (if include_rows (:queries exec) {})
      :facts_count (count (:facts exec))
      :declarations_count (count declarations)})))

(defn query-ci-program
  "Parse + compile + run query CI over ZIL source text."
  ([text]
   (query-ci-program text {}))
  ([text opts]
   (-> text
       compile-program
       (query-ci-compiled opts))))

(defn query-ci-file
  "Read source file and run query CI."
  ([path]
   (query-ci-file path {}))
  ([path opts]
   (query-ci-program (slurp path) opts)))

(defn execute-program
  "Parse + compile + execute Zil source text."
  [text]
  (-> text
      compile-program
      execute-compiled))

(defn compile-file
  "Parse + compile (stratify) Zil source from file path, without evaluating rules."
  ([path] (compile-program (slurp path)))
  ([path opts] (compile-program (slurp path) opts)))

(defn execute-file
  "Read and execute Zil source from file path."
  [path]
  (execute-program (slurp path)))

(defn materialize-datascript
  "Execute program and return the DataScript conn produced by execution.

  Returns {:conn ..., :result ...}.
  The conn holds all base + derived facts at revision 0."
  ([text] (materialize-datascript text {}))
  ([text _opts]
   (let [result (execute-program text)]
     {:conn (:conn result) :result result})))
