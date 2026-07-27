(ns zil.bridge.souffle
  "Souffle Datalog bridge for ZIL.

  Translates a compiled ZIL program (facts + rules + queries) to a Souffle .dl
  schema + fact TSV files, executes via subprocess, and parses TSV output.

  Performance design:
  - Base facts are written to separate <relation>.facts TSV files and loaded
    via .input directives with -F <dir>.  This keeps ALL ground atoms out of
    the .dl file so Souffle's analysis pipeline (SubsumptionQualifier,
    SemanticChecker, MinimiseProgramTransformer) only sees the rule clauses.
    On large fact-heavy models this drops execution time from ~85s to ~1-2s.
  - The attrs column is omitted from every relation (.decl uses 2 columns).
    Every ZIL rule body already wildcards attrs, so the third column is dead
    weight that doubles the join search space.

  Wire format:
  - .dl file: .decl, .input (base), .decl (derived), rules, .decl/.output (queries)
  - .facts files: raw tab-separated  object TAB subject  (one row per fact)
  - Souffle invoked: souffle -D- -F <facts-dir> -j<N> <schema.dl>
  - Results parsed from Souffle's sectioned stdout TSV format."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]))

;; ---------------------------------------------------------------------------
;; Naming helpers
;; ---------------------------------------------------------------------------

(defn souffle-rel-name
  "Map a ZIL relation keyword to a Souffle relation name."
  [relation]
  (str "zil_" (-> relation name (str/replace #"[^a-zA-Z0-9_]" "_"))))

(defn- souffle-escape-str
  "Escape a string for use inside a Souffle .dl double-quoted string literal."
  [s]
  (-> (str s)
      (str/replace "\\" "\\\\")
      (str/replace "\"" "\\\"")))

(defn- souffle-val
  "Encode a ZIL term value as a Souffle .dl string literal (used in rule/query bodies)."
  [v]
  (str "\"" (souffle-escape-str (if (nil? v) "nil" (str v))) "\""))

(defn- tsv-escape
  "Escape a value for writing to a Souffle .facts TSV file.
  Tabs and newlines in values are escaped so they don't break the TSV format."
  [v]
  (-> (if (nil? v) "" (str v))
      (str/replace "\\" "\\\\")
      (str/replace "\t" "\\t")
      (str/replace "\n" "\\n")
      (str/replace "\r" "\\r")))

;; ---------------------------------------------------------------------------
;; Variable translation
;; ---------------------------------------------------------------------------

(defn- zil-var? [t] (and (string? t) (str/starts-with? t "?")))

(defn- var->souffle
  "?foo → FOO  (Souffle variables must be uppercase)"
  [v]
  (-> v (subs 1) str/upper-case (str/replace #"[^A-Z0-9_]" "_")))

(defn- term->souffle
  "Translate a ZIL object/subject term to a Souffle .dl argument."
  [t]
  (if (zil-var? t) (var->souffle t) (souffle-val t)))

;; ---------------------------------------------------------------------------
;; Fact TSV files  (facts → one .facts file per relation)
;; ---------------------------------------------------------------------------

(defn write-facts-dir!
  "Write one <relation>.facts TSV file per distinct relation in `facts`.
  Each file: one line per fact, two tab-separated columns: object TAB subject.
  Returns the facts directory path (string)."
  ([facts] (write-facts-dir! facts nil))
  ([facts dir-path]
   (let [dir (if dir-path
               (doto (io/file dir-path) .mkdirs)
               (let [d (java.io.File/createTempFile "zil_facts_" "")]
                 (.delete d) (.mkdirs d) d))
         by-rel (group-by :relation facts)]
     (doseq [[rel rows] by-rel]
       (let [f (io/file dir (str (souffle-rel-name rel) ".facts"))]
         (with-open [w (io/writer f)]
           (doseq [{:keys [object subject]} rows]
             (.write w (str (tsv-escape object) "\t" (tsv-escape subject) "\n"))))))
     (.getAbsolutePath dir))))

;; ---------------------------------------------------------------------------
;; Schema (.dl) — decls + .input + rules + query outputs
;; ---------------------------------------------------------------------------

(defn- base-rel-input-decls
  "Emit .decl + .input directives for base fact relations.
  Facts are loaded from <relation>.facts in the Souffle fact directory (-F)."
  [facts]
  (->> facts
       (map :relation)
       distinct
       sort
       (mapcat (fn [rel]
                 [(str ".decl " (souffle-rel-name rel) "(object:symbol, subject:symbol)")
                  (str ".input " (souffle-rel-name rel)
                       "(IO=file, filename=\"" (souffle-rel-name rel) ".facts\""
                       ", delimiter=\"\\t\")")]))))

;; ---------------------------------------------------------------------------
;; Literal translation (rules and query bodies)
;; ---------------------------------------------------------------------------

(defn- term->souffle-safe
  "Like term->souffle, but replaces unbound ZIL variables with Souffle wildcard _.
  Used in negated literals where a variable may not appear in any positive literal."
  [t bound-vars]
  (if (and (zil-var? t) (not (contains? bound-vars t)))
    "_"
    (term->souffle t)))

(defn- literal->souffle
  "Translate a ZIL literal to a Souffle body clause.
  All relations use 2-arg form (object, subject) — attrs column is omitted.
  bound-vars: set of ZIL variable strings bound by preceding positive literals;
  used to replace unbound vars in negated literals with Souffle wildcard _."
  ([lit derived-rels] (literal->souffle lit derived-rels nil))
  ([{:keys [object relation subject neg?]} _derived-rels bound-vars]
   (let [obj-t (if (and neg? bound-vars) (term->souffle-safe object bound-vars) (term->souffle object))
         sub-t (if (and neg? bound-vars) (term->souffle-safe subject bound-vars) (term->souffle subject))
         body  (str (souffle-rel-name relation) "(" obj-t ", " sub-t ")")]
     (if neg? (str "!" body) body))))

;; ---------------------------------------------------------------------------
;; Rules → .decl + :- lines
;; ---------------------------------------------------------------------------

(defn- collect-rule-derived-rels
  [rules]
  (into #{} (mapcat #(map :relation (:then %)) rules)))

(defn- lit-vars
  "Return the set of ZIL variable strings appearing in a literal's object and subject."
  [{:keys [object subject]}]
  (into #{} (filter zil-var? [object subject])))

(defn- rule-souffle-safe?
  "True when every variable in the THEN head is bound by a positive IF body literal.
  Unsafe rules produce ungrounded Souffle variables and are skipped."
  [{:keys [if then]}]
  (let [pos-vars  (into #{} (mapcat lit-vars) (remove :neg? if))
        head-vars (into #{} (mapcat lit-vars) then)]
    (clojure.set/subset? head-vars pos-vars)))

(defn- query-souffle-safe?
  "True when every FIND variable is bound by a positive WHERE literal."
  [{:keys [find where]}]
  (let [pos-vars  (into #{} (mapcat lit-vars) (remove :neg? where))
        find-vars (set find)]
    (clojure.set/subset? find-vars pos-vars)))

;; ---------------------------------------------------------------------------
;; Self-negation cycle breaker
;; ---------------------------------------------------------------------------

(defn- self-neg-patterns
  "Return #{[rel subj]} pairs where a derived rule negates its own relation
  with a constant subject.  These cause Souffle stratification failures."
  [rules]
  (let [derived (collect-rule-derived-rels rules)]
    (into #{}
          (for [rule  rules
                neg   (filter :neg? (:if rule))
                :let  [rel  (:relation neg)
                       subj (:subject neg)]
                :when (contains? derived rel)
                :when (not (zil-var? subj))
                :when (some #(= (:relation %) rel) (:then rule))]
            [rel subj]))))

(defn- aux-rel-kw
  "Keyword for the auxiliary relation that breaks a self-neg cycle for [rel subj]."
  [[rel subj]]
  (keyword (str (name rel) "__aux_"
                (-> (str subj)
                    (str/replace #"[^a-zA-Z0-9]" "_")
                    str/lower-case))))

(defn- break-self-neg-cycles
  "Eliminate Souffle stratification cycles caused by a derived relation negating itself.

  For each self-negating (rel, const-subj) pattern:
  1. Introduce rel_aux(obj, \"value:true\") — derived from the same body as the
     rule that produces rel(obj, const-subj).
  2. Rewrite any !rel(X, const-subj) literal → !rel_aux(X, \"value:true\").

  The original source rule is kept unchanged.  Now rel no longer depends on !rel."
  [rules]
  (let [patterns (self-neg-patterns rules)]
    (if (empty? patterns)
      rules
      (let [aux-map  (into {} (map (fn [p] [p (aux-rel-kw p)]) patterns))
            ;; Rewrite body negations that match a cycle pattern
            rewrite-lits
            (fn [lits]
              (mapv (fn [lit]
                      (if-not (:neg? lit)
                        lit
                        (let [k [(:relation lit) (:subject lit)]]
                          (if-let [aux (get aux-map k)]
                            (assoc lit :relation aux :subject "value:true")
                            lit))))
                    lits))
            rewritten (mapv #(update % :if rewrite-lits) rules)
            ;; Build auxiliary rules
            aux-rules
            (mapcat
             (fn [[rel subj :as pattern]]
               (let [aux (get aux-map pattern)
                     ;; Rules that directly produce rel(X, subj) in their head
                     sources (filter
                              (fn [r]
                                (some #(and (= (:relation %) rel) (= (:subject %) subj))
                                      (:then r)))
                              rules)]
                 (mapv (fn [src]
                         (let [heads (filter #(and (= (:relation %) rel)
                                                   (= (:subject %) subj))
                                             (:then src))]
                           {:name (str "aux_" (name aux))
                            :if   (:if src)
                            :then (mapv #(assoc % :relation aux :subject "value:true")
                                        heads)}))
                       sources)))
             patterns)]
        (concat rewritten aux-rules)))))

;; ---------------------------------------------------------------------------
;; Souffle-safe fact-file creator
;; ---------------------------------------------------------------------------

(defn create-empty-fact-files!
  "Create empty .facts files for every .input-declared relation that does not
  already have a file in `facts-dir`.  Souffle requires the file to exist even
  for empty relations."
  [dl-text facts-dir]
  (let [rels (->> (str/split-lines (or dl-text ""))
                  (keep #(second (re-find #"^\.input\s+(\w+)\s*\(" %))))]
    (doseq [rel rels]
      (let [f (io/file facts-dir (str rel ".facts"))]
        (when-not (.exists f)
          (spit f ""))))))

(defn rules->souffle
  "Emit .decl for derived relations + Souffle rule :- lines.
  base-rels: set of relations already declared as base (.decl+.input) — skip their decls."
  ([rules] (rules->souffle rules #{}))
  ([rules base-rels]
   (let [rules*       (break-self-neg-cycles rules)
         derived-rels (collect-rule-derived-rels rules*)
         new-derived  (remove base-rels (sort derived-rels))
         decls (mapv (fn [rel]
                       (str ".decl " (souffle-rel-name rel)
                            "(object:symbol, subject:symbol)"))
                     new-derived)
         rule-lines
         (mapcat
          (fn [{:keys [if then] :as rule}]
            (if-not (rule-souffle-safe? rule)
              []  ;; skip rules whose head vars are not bound in the body
              (let [pos-lits   (remove :neg? if)
                    bound-vars (into #{} (mapcat (fn [{:keys [object subject]}]
                                                   (filter zil-var? [object subject]))
                                                 pos-lits))
                    body-terms (map #(literal->souffle % derived-rels bound-vars) if)
                    body-str   (str/join ",\n  " body-terms)]
                (mapv (fn [{:keys [object relation subject]}]
                        (str (souffle-rel-name relation)
                             "(" (term->souffle object) ", " (term->souffle subject) ") :-\n"
                             "  " body-str "."))
                      then))))
          rules*)]
     (str/join "\n" (concat decls [""] rule-lines)))))

;; ---------------------------------------------------------------------------
;; Queries → .decl + .output + rule
;; ---------------------------------------------------------------------------

(defn queries->souffle
  "Emit .decl + .output(IO=stdout) + rule body for each ZIL query.
  Queries whose FIND variables are not fully bound in the WHERE body receive
  only .decl + .output (no rule) and will return 0 rows."
  [queries derived-rels]
  (->> queries
       (mapv (fn [{:keys [name find where] :as q}]
               (let [find-vars  (mapv var->souffle find)
                     decl-args  (str/join ", " (map #(str % ":symbol") find-vars))
                     rule-str
                     (when (query-souffle-safe? q)
                       (let [pos-lits   (remove :neg? where)
                             bound-vars (into #{} (mapcat (fn [{:keys [object subject]}]
                                                            (filter zil-var? [object subject]))
                                                          pos-lits))
                             body-terms (map #(literal->souffle % derived-rels bound-vars) where)
                             body-str   (str/join ",\n  " body-terms)]
                         (str name "(" (str/join ", " find-vars) ") :-\n"
                              "  " body-str ".")))]
                 (str/join "\n"
                   (filter some?
                     [(str ".decl " name "(" decl-args ")")
                      (str ".output " name "(IO=stdout, delimiter=\"\\t\")")
                      rule-str])))))))

;; ---------------------------------------------------------------------------
;; Schema assembly  (no ground atoms — facts go to TSV files)
;; ---------------------------------------------------------------------------

(defn- collect-body-rels
  "Collect all relations referenced in rule/query bodies."
  [rules queries]
  (into #{}
        (concat (mapcat #(map :relation (:if %)) rules)
                (mapcat #(map :relation (:where %)) queries))))

(defn emit-souffle-schema
  "Emit the .dl schema string for `compiled`.
  Contains .decl+.input for base relations, .decl for derived relations,
  rule :- clauses, and .decl+.output for query relations.
  Ground facts are NOT included — they live in separate .facts TSV files."
  [{:keys [facts rules queries]}]
  (let [base-rels    (into #{} (map :relation facts))
        derived-rels (collect-rule-derived-rels rules)
        body-rels    (collect-body-rels rules queries)
        ;; Relations used in bodies but neither base nor derived → emit empty .decl+.input
        undeclared   (->> body-rels
                          (remove base-rels)
                          (remove derived-rels)
                          sort)
        undeclared-decls (mapcat (fn [rel]
                                   [(str ".decl " (souffle-rel-name rel) "(object:symbol, subject:symbol)")
                                    (str ".input " (souffle-rel-name rel)
                                         "(IO=file, filename=\"" (souffle-rel-name rel) ".facts\""
                                         ", delimiter=\"\\t\")")])
                                 undeclared)
        sections
        (cond-> []
          true
          (conj (str/join "\n" (concat (base-rel-input-decls facts) undeclared-decls)))
          (seq rules)
          (conj (rules->souffle rules base-rels))
          (seq queries)
          (conj (str/join "\n\n" (queries->souffle queries derived-rels))))]
    (str/join "\n\n" sections)))

(defn emit-souffle-program
  "Assemble a self-contained .dl program (schema + ground-fact atoms).
  Suitable for inspection or offline sharing; NOT used by execute-with-souffle
  (which uses the faster facts-dir path via emit-souffle-schema)."
  [{:keys [facts rules queries] :as compiled}]
  (let [derived-rels (collect-rule-derived-rels rules)
        fact-decls (->> facts
                        (map :relation)
                        distinct
                        sort
                        (mapv (fn [rel]
                                (str ".decl " (souffle-rel-name rel)
                                     "(object:symbol, subject:symbol)"))))
        fact-lines (->> facts
                        (mapv (fn [{:keys [object relation subject]}]
                                (str (souffle-rel-name relation)
                                     "(" (souffle-val object) ", "
                                     (souffle-val subject) ")."))))
        sections
        (cond-> []
          (seq facts)
          (conj (str/join "\n" (concat fact-decls [""] fact-lines)))
          (seq rules)
          (conj (rules->souffle rules))
          (seq queries)
          (conj (str/join "\n\n" (queries->souffle queries derived-rels))))]
    (str/join "\n\n" sections)))

;; ---------------------------------------------------------------------------
;; Subprocess runner
;; ---------------------------------------------------------------------------

(defn run-souffle
  "Write `dl-text` to a temp .dl file and `facts-dir` to a temp directory,
  invoke Souffle with -F <facts-dir>, return stdout string.

  Options:
  :souffle-bin  — path to souffle binary (default \"souffle\")
  :parallel     — -j<N> worker threads (default 1)
  :extra-args   — extra CLI args (default [])

  Throws ex-info when souffle exits non-zero."
  [dl-text facts-dir {:keys [souffle-bin parallel extra-args]
                      :or {souffle-bin "souffle" parallel 1 extra-args []}}]
  (let [dl-file (java.io.File/createTempFile "zil_souffle_" ".dl")]
    (try
      (spit dl-file dl-text)
      (let [cmd (into [souffle-bin
                       "-D-"
                       "-F" facts-dir
                       (str "-j" parallel)
                       (.getAbsolutePath dl-file)]
                      extra-args)
            pb (doto (ProcessBuilder. ^java.util.List cmd)
                 (.redirectErrorStream true))
            proc (.start pb)
            stdout (slurp (.getInputStream proc))
            exit (.waitFor proc)]
        (when (not (zero? exit))
          (throw (ex-info "Souffle exited with non-zero status"
                          {:exit exit :output stdout :dl-file (.getAbsolutePath dl-file)})))
        stdout)
      (finally
        (.delete dl-file)))))

(defn- delete-dir!
  [path]
  (let [f (io/file path)]
    (when (.exists f)
      (doseq [child (.listFiles f)] (.delete child))
      (.delete f))))

;; ---------------------------------------------------------------------------
;; TSV output parser
;; ---------------------------------------------------------------------------

(defn- parse-souffle-stdout
  "Parse Souffle -D- stdout into {relation-name -> [[row...]...]}.

  Format per relation:
    ---------------          <- dash separator
    relation_name
    col_header1\\tcol2       <- column header row — skip
    ===============          <- data start
    row values...
    ===============          <- data end"
  [stdout]
  (let [lines (str/split-lines (or stdout ""))
        dash-sep?  #(str/starts-with? % "---------------")
        equal-sep? #(str/starts-with? % "===============")]
    (loop [remaining lines
           state     :idle
           current-rel nil
           current-rows []
           acc {}]
      (if (empty? remaining)
        (cond-> acc
          (and current-rel (seq current-rows))
          (assoc current-rel (vec current-rows)))
        (let [line  (first remaining)
              rest* (rest remaining)]
          (case state
            :idle
            (recur rest* (if (dash-sep? line) :rel-name :idle) nil [] acc)

            :rel-name
            (if (str/blank? line)
              (recur rest* :rel-name nil [] acc)
              (recur rest* :col-header (str/trim line) [] acc))

            :col-header
            (recur rest* (if (equal-sep? line) :data :col-header) current-rel [] acc)

            :data
            (cond
              (equal-sep? line)
              (recur rest* :idle nil []
                     (assoc acc current-rel (vec current-rows)))
              (dash-sep? line)
              (recur rest* :rel-name nil []
                     (assoc acc current-rel (vec current-rows)))
              (str/blank? line)
              (recur rest* :data current-rel current-rows acc)
              :else
              (recur rest* :data current-rel
                     (conj current-rows (str/split line #"\t" -1)) acc))))))))

;; ---------------------------------------------------------------------------
;; Main entry point
;; ---------------------------------------------------------------------------

(defn execute-with-souffle
  "Execute a compiled ZIL program using Souffle as the Datalog engine.

  `compiled` — {:facts [...] :rules [...] :queries [...]}
  `opts`     — {:souffle-bin :parallel :extra-args}

  Returns:
  {:query-results {query-name {:vars [...] :rows [[...]]}}
   :facts-dir     <path to temp .facts directory>
   :dl            <schema .dl string>
   :stdout        <raw Souffle output>}"
  [compiled opts]
  (let [facts-dir (write-facts-dir! (:facts compiled))
        dl-text   (emit-souffle-schema compiled)
        _         (create-empty-fact-files! dl-text facts-dir)]
    (try
      (let [stdout  (run-souffle dl-text facts-dir opts)
            parsed  (parse-souffle-stdout stdout)
            qr      (into {}
                          (for [{:keys [name find]} (:queries compiled)
                                :let [rows (get parsed name [])]]
                            [name {:vars find :rows (vec (sort rows))}]))]
        {:query-results qr
         :facts-dir     facts-dir
         :dl            dl-text
         :stdout        stdout})
      (finally
        (delete-dir! facts-dir)))))

(defn souffle-available?
  "True when `souffle` (or the configured binary) is on PATH and responds to --version."
  ([] (souffle-available? "souffle"))
  ([souffle-bin]
   (try
     (let [pb (doto (ProcessBuilder. [souffle-bin "--version"])
                (.redirectErrorStream true))
           proc (.start pb)
           _    (slurp (.getInputStream proc))
           exit (.waitFor proc)]
       (zero? exit))
     (catch Exception _ false))))
