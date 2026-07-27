(ns zil.bridge.proof-obligation
  "Execute PROOF_OBLIGATION declarations through available tool backends.

  Current implementation supports:
  - tool=z3 (direct SMT solver checks)
  - tool=acl2 (artifact/log evidence mode and optional command mode)
  Other tools are currently reported as skipped/unsupported."
  (:require [clojure.java.io :as io]
            [clojure.java.shell :as sh]
            [clojure.string :as str]
            [zil.bridge.tla :as bt]
            [zil.core :as core]
            [zil.lower :as zl]
            [zil.preprocess :as zp]
            [zil.profile.z3 :as z3]))

(defn- token->name
  [v]
  (cond
    (string? v) v
    (keyword? v) (name v)
    (symbol? v) (name v)
    :else (str v)))

(defn- token->kw
  [v]
  (when (some? v)
    (let [n (-> (token->name v)
                str/trim
                str/lower-case)]
      (when-not (str/blank? n)
        (keyword n)))))

(def macro-header-re
  #"(?i)^MACRO\s+[A-Za-z0-9_.:-]+\s*\(.*\)\s*:\s*$")

(def macro-end-re
  #"(?i)^ENDMACRO\.\s*$")

(defn- collect-macro-only-lines
  [text]
  (let [lines (core/preprocess-lines text)
        n (count lines)]
    (loop [i 0
           out []]
      (if (>= i n)
        out
        (let [line (nth lines i)]
          (if (re-matches macro-header-re line)
            (let [[next-i block]
                  (loop [j i
                         block []]
                    (when (>= j n)
                      (throw (ex-info "Unterminated macro block while collecting macro-only libs."
                                      {:line line})))
                    (let [row (nth lines j)
                          block* (conj block row)]
                      (if (re-matches macro-end-re row)
                        [(inc j) block*]
                        (recur (inc j) block*))))]
              (recur next-i (into out block)))
            (recur (inc i) out)))))))

(defn- compile-with-macro-only-libs
  [path]
  (let [model-text (slurp path)
        lib-files (zp/collect-lib-zc-files path nil)
        macro-lines (->> lib-files
                         (mapcat #(collect-macro-only-lines (slurp %)))
                         vec)
        merged-text (str (str/join "\n" macro-lines)
                         (when (seq macro-lines) "\n")
                         model-text)]
    {:ok true
     :file path
     :compiled (core/compile-program merged-text)
     :preprocessed true
     :preprocess_mode :macro_only
     :lib_files (mapv #(.getAbsolutePath ^java.io.File %) lib-files)}))

(defn- compile-file
  [path]
  (let [text (slurp path)]
    (try
      {:ok true
       :file path
       :compiled (core/compile-program text)
       :preprocessed false}
      (catch clojure.lang.ExceptionInfo e
        (if (re-find #"Unknown macro invocation" (.getMessage e))
          (try
            (compile-with-macro-only-libs path)
            (catch Exception _
              (try
                (let [pp (zp/preprocess-model path {})
                      compiled (core/compile-program (:text pp))]
                  {:ok true
                   :file path
                   :compiled compiled
                   :preprocessed true
                   :preprocess_mode :full_lib
                   :lib_files (:lib_files pp)})
                (catch Exception e2
                  {:ok false
                   :file path
                   :error (.getMessage e2)}))))
          {:ok false
           :file path
           :error (.getMessage e)}))
      (catch Exception e
        {:ok false
         :file path
         :error (.getMessage e)}))))

(defn- resolve-tool-filter
  [tool]
  (let [tk (token->kw tool)]
    (when-not (or (nil? tk) (= :all tk) (= :* tk))
      tk)))

(defn- normalize-proof-obligation
  [{:keys [name attrs]}]
  (let [decl* (zl/normalized-declaration {:kind :proof_obligation
                                          :name name
                                          :attrs attrs})
        attrs* (:attrs decl*)]
    {:id (zl/entity-id :proof_obligation (:name decl*))
     :name (:name decl*)
     :relation (token->name (:relation attrs*))
     :statement (str (:statement attrs*))
     :tool (token->kw (:tool attrs*))
     :logic (token->kw (:logic attrs*))
     :expectation (token->kw (:expectation attrs*))
     :criticality (token->kw (:criticality attrs*))
     :command (:command attrs*)
     :artifact_in (:artifact_in attrs*)
     :artifact_out (:artifact_out attrs*)
     :attrs attrs*}))

(defn- collect-obligations
  [path]
  (let [files (bt/collect-zc-files path)]
    (when (empty? files)
      (throw (ex-info "No .zc files found in path for proof-obligation-check."
                      {:path path})))
    (let [results (mapv compile-file files)
          failed (vec (filter (complement :ok) results))]
      (when (seq failed)
        (throw (ex-info "Failed to parse .zc file for proof-obligation-check."
                        {:path path
                         :errors (mapv #(select-keys % [:file :error]) failed)})))
      {:files files
       :obligations
       (mapv (fn [{:keys [file compiled]}]
               (mapv (fn [decl]
                       (assoc (normalize-proof-obligation decl)
                              :file file
                              :module (:module compiled)))
                     (filter #(= :proof_obligation (:kind %))
                             (:declarations compiled))))
             results)})))

(defn- flatten-obligations
  [nested]
  (vec (mapcat identity nested)))

(defn- z3-verdict
  [solver-status expectation]
  (case solver-status
    :sat (if (= expectation :sat) :satisfied :violated)
    :unsat (if (= expectation :unsat) :satisfied :violated)
    :unknown :unknown
    :unavailable :error
    :error :error
    :error))

(defn- run-z3-obligation
  [{:keys [statement logic expectation] :as obligation}]
  (let [logic-token (or logic :all)
        expectation* (or expectation :sat)
        check (z3/check-conditions [statement] {:logic logic-token})
        verdict (z3-verdict (:status check) expectation*)]
    (merge
     obligation
     {:backend :z3
      :status verdict
      :solver_status (:status check)
      :ok (= verdict :satisfied)
      :error (:error check)
      :logic (:logic check)
      :script (:script check)
      :sorts (:sorts check)
      :symbols (:symbols check)})))

(def acl2-success-patterns
  [#"(?i)\bQ\.E\.D\."
   #"(?i)\bproved\b"
   #"(?i)\bproof succeeded\b"])

(def acl2-failure-patterns
  [#"(?i)\bACL2 Error\b"
   #"(?i)\bHARD ACL2 ERROR\b"
   #"(?i)\bFAILED\b"
   #"(?i)\bproof failed\b"])

(defn- acl2-log->solver-status
  [text]
  (let [txt (or text "")
        failed? (boolean (some #(re-find % txt) acl2-failure-patterns))
        proved? (boolean (some #(re-find % txt) acl2-success-patterns))]
    (cond
      failed? :failed
      proved? :proved
      :else :unknown)))

(defn- acl2-verdict
  [solver-status expectation]
  (case solver-status
    :proved (if (= expectation :unsat) :violated :satisfied)
    :failed (if (= expectation :unsat) :satisfied :violated)
    :unknown :unknown
    :unavailable :error
    :error))

(defn- resolve-artifact-in-path
  [{:keys [artifact_in file]}]
  (when artifact_in
    (let [raw (token->name artifact_in)
          f (io/file raw)]
      (if (.isAbsolute f)
        (.getAbsolutePath f)
        (let [base (some-> file io/file .getParentFile)]
          (if base
            (.getAbsolutePath (io/file base raw))
            (.getAbsolutePath f)))))))

(defn- resolve-artifact-out-path
  [{:keys [artifact_out file]}]
  (when artifact_out
    (let [raw (token->name artifact_out)
          f (io/file raw)]
      (if (.isAbsolute f)
        (.getAbsolutePath f)
        (let [base (some-> file io/file .getParentFile)]
          (if base
            (.getAbsolutePath (io/file base raw))
            (.getAbsolutePath f)))))))

(defn- write-artifact-out!
  [path content]
  (when path
    (let [f (io/file path)
          p (.getParentFile f)]
      (when p
        (.mkdirs p))
      (spit f (or content "")))
    path))

(defn- run-acl2-command
  [cmd]
  (let [res (sh/sh "sh" "-lc" cmd)
        text (str (:out res) (:err res))
        parsed (acl2-log->solver-status text)
        solver-status (if (and (not= 0 (:exit res))
                               (= :unknown parsed))
                        :failed
                        parsed)]
    {:exit (:exit res)
     :text text
     :solver_status solver-status}))

(defn- run-acl2-obligation
  [{:keys [expectation command] :as obligation}]
  (let [expectation* (or expectation :sat)
        artifact-in-path (resolve-artifact-in-path obligation)
        artifact-out-path (resolve-artifact-out-path obligation)]
    (cond
      (and artifact-in-path (.exists (io/file artifact-in-path)))
      (let [content (slurp artifact-in-path)
            solver-status (acl2-log->solver-status content)
            verdict (acl2-verdict solver-status expectation*)]
        (merge obligation
               {:backend :acl2
                :mode :artifact
                :artifact_path artifact-in-path
                :solver_status solver-status
                :status verdict
                :ok (= verdict :satisfied)}))

      command
      (let [result (run-acl2-command (token->name command))
            verdict (acl2-verdict (:solver_status result) expectation*)]
        (write-artifact-out! artifact-out-path (:text result))
        (merge obligation
               {:backend :acl2
                :mode :command
                :command (token->name command)
                :command_exit (:exit result)
                :artifact_path artifact-out-path
                :solver_status (:solver_status result)
                :status verdict
                :ok (= verdict :satisfied)}))

      :else
      (merge obligation
             {:backend :acl2
              :mode :artifact
              :artifact_path artifact-in-path
              :solver_status :unavailable
              :status :unknown
              :ok false
              :error "ACL2 evidence missing. Provide artifact_in=<acl2-log> or command=<acl2-run-command>."}))))

(defn- run-obligation
  [{:keys [tool] :as obligation}]
  (case tool
    :z3 (run-z3-obligation obligation)
    :acl2 (run-acl2-obligation obligation)
    (assoc obligation
           :backend tool
           :status :skipped
           :ok true
           :error (str "Tool backend not implemented yet: " (name tool)))))

(defn- status-counts
  [rows]
  (reduce (fn [m {:keys [status]}]
            (update m status (fnil inc 0)))
          {:satisfied 0
           :violated 0
           :unknown 0
           :error 0
           :skipped 0}
          rows))

(defn run-proof-obligation-check
  "Run proof-obligation checks over a .zc file or directory.

  Options:
  - :tool tool filter (`z3`, `lean4`, `tlaps`, `acl2`, `manual`, or `all`)

  Returns a report with per-obligation status and gate summary.
  `:ok` is false if any evaluated obligation is violated/unknown/error."
  ([path]
   (run-proof-obligation-check path {}))
  ([path {:keys [tool]}]
   (let [tool-filter (resolve-tool-filter tool)
         {:keys [files obligations]} (collect-obligations path)
         obligations* (->> (flatten-obligations obligations)
                           (filter (fn [{:keys [tool]}]
                                     (or (nil? tool-filter)
                                         (= tool-filter tool))))
                           vec)
         evaluated (mapv run-obligation obligations*)
         counts (status-counts evaluated)
         blocking (+ (get counts :violated 0)
                     (get counts :unknown 0)
                     (get counts :error 0))]
     {:ok (zero? blocking)
      :path path
      :files files
      :tool_filter (or tool-filter :all)
      :obligation_count (count obligations*)
      :evaluated_count (count (remove #(= :skipped (:status %)) evaluated))
      :status_counts counts
      :obligations (vec (sort-by (juxt :module :name) evaluated))})))
