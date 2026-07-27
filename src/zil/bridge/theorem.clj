(ns zil.bridge.theorem
  "Bridge helpers to generate formal sidecar skeletons from theorem contracts.

  Input theorem contracts are represented as canonical facts, for example:
  - theorem:<id>#kind@entity:theorem.
  - theorem:<id>#requires_assumption@assumption:<aid>.
  - theorem:<id>#requires_lemma@lemma:<lid>.
  - theorem:<id>#criticality@value:high.
  - theorem:<id>#ensures@guarantee:<g>.

  Output is a generated .zc module with:
  - one LTS_ATOM skeleton per theorem
  - two POLICY skeletons per theorem (requirements + proof soundness)."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.bridge.tla :as bt]
            [zil.core :as core]
            [zil.preprocess :as zp]))

(defn- token->name
  [v]
  (cond
    (string? v) v
    (keyword? v) (name v)
    (symbol? v) (name v)
    :else (str v)))

(defn- safe-ident
  [x]
  (-> (str x)
      (str/replace #"[^A-Za-z0-9_.:-]" "_")
      (str/replace #"_+" "_")
      (str/replace #"^_+" "")
      (str/replace #"_+$" "")))

(defn- safe-var
  [x]
  (let [s (-> (str x)
              (str/replace #"[^A-Za-z0-9_]" "_")
              (str/replace #"_+" "_")
              (str/replace #"^_+" "")
              (str/replace #"_+$" ""))]
    (if (str/blank? s) "v" s)))

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
  (let [token (str/lower-case (str part))]
    (if (str/blank? token)
      ""
      (str (str/upper-case (subs token 0 1))
           (subs token 1)))))

(defn- to-pascal-ident
  [s]
  (let [parts (tokenize-ident s)]
    (if (empty? parts)
      "Theorem"
      (apply str (map pascalize-part parts)))))

(defn- to-lower-ident
  [s]
  (let [parts (tokenize-ident s)]
    (if (empty? parts)
      "theorem"
      (let [head (str/lower-case (first parts))
            tail (map pascalize-part (rest parts))]
        (apply str head tail)))))

(defn- unprefix
  [prefix s]
  (let [txt (token->name s)]
    (if (str/starts-with? txt prefix)
      (subs txt (count prefix))
      txt)))

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
            (let [pp (zp/preprocess-model path {})
                  compiled (core/compile-program (:text pp))]
              {:ok true
               :file path
               :compiled compiled
               :preprocessed true
               :lib_files (:lib_files pp)})
            (catch Exception e2
              {:ok false
               :file path
               :error (.getMessage e2)}))
          {:ok false
           :file path
           :error (.getMessage e)}))
      (catch Exception e
        {:ok false
         :file path
         :error (.getMessage e)}))))

(defn- theorem-objects
  [facts]
  (->> facts
       (filter (fn [{:keys [object relation subject]}]
                 (and (= :kind relation)
                      (= "entity:theorem" (token->name subject))
                      (string? object)
                      (str/starts-with? object "theorem:"))))
       (map :object)
       distinct
       sort
       vec))

(defn- rel-values
  [facts rel]
  (->> facts
       (filter #(= rel (:relation %)))
       (map (comp token->name :subject))
       distinct
       sort
       vec))

(defn- theorem-criticality
  [facts]
  (let [raw (some-> (first (rel-values facts :criticality))
                    (#(unprefix "value:" %))
                    str/lower-case)
        allowed #{"low" "medium" "high" "critical"}]
    (if (contains? allowed raw) raw "low")))

(defn- theorem-contracts-from-facts
  [facts]
  (let [by-object (group-by :object facts)
        objs (theorem-objects facts)]
    (mapv
     (fn [obj]
       (let [id (unprefix "theorem:" obj)
             fs (get by-object obj [])
             assumptions (->> (rel-values fs :requires_assumption)
                              (map #(unprefix "assumption:" %))
                              vec)
             lemmas (->> (rel-values fs :requires_lemma)
                         (map #(unprefix "lemma:" %))
                         vec)
             ensures (->> (rel-values fs :ensures)
                          (map #(unprefix "guarantee:" %))
                          vec)]
         {:id id
          :criticality (theorem-criticality fs)
          :assumptions assumptions
          :lemmas lemmas
          :ensures ensures}))
     objs)))

(defn- requirement-expr
  [{:keys [assumptions lemmas]}]
  (let [terms (concat (map #(str "assumption_" (safe-var %) "_holds") assumptions)
                      (map #(str "lemma_" (safe-var %) "_proved") lemmas))]
    (if (empty? terms)
      "true"
      (str/join " AND " terms))))

(defn- render-theorem-block
  [{:keys [id criticality assumptions lemmas ensures]}]
  (let [sid (safe-ident id)
        actor (safe-ident (str "Theorem" (to-pascal-ident id)))
        actor-key (safe-ident (str "theorem" (to-pascal-ident id)))
        lts-name (safe-ident (str "theorem_" sid "_flow"))
        req-policy (safe-ident (str "theorem_" sid "_requirements"))
        sound-policy (safe-ident (str "theorem_" sid "_proof_soundness"))
        req (requirement-expr {:assumptions assumptions :lemmas lemmas})
        proved-var (str "theorem_" (safe-var sid) "_is_proved")
        soundness (str proved-var " IMPLIES (" req ")")]
    (str
     "// theorem: " id "\n"
     (when (seq ensures)
       (str "// ensures: " (str/join ", " ensures) "\n"))
     (when (seq assumptions)
       (str "// requires assumptions: " (str/join ", " assumptions) "\n"))
     (when (seq lemmas)
       (str "// requires lemmas: " (str/join ", " lemmas) "\n"))
     "LTS_ATOM " lts-name
     " [actor=" actor
     ", actor_key=" actor-key
     ", states=#{contract_defined obligations_open proved conditional broken weak}"
     ", initial=contract_defined"
     ", transitions={[contract_defined open_obligations] [obligations_open],"
     " [contract_defined proof_missing] [weak],"
     " [obligations_open discharge_all] [proved],"
     " [obligations_open assumptions_partial] [conditional],"
     " [obligations_open dependency_break] [broken],"
     " [conditional discharge_all] [proved],"
     " [weak proof_added] [obligations_open],"
     " [proved dependency_break] [broken],"
     " [broken repair_dependencies] [obligations_open]}].\n\n"
     "POLICY " req-policy
     " [condition=\"" req "\", criticality=" criticality "].\n"
     "POLICY " sound-policy
     " [condition=\"" soundness "\", criticality=" criticality "].\n")))

(defn- sanitize-module-name
  [s]
  (let [clean (-> (or s "theorem.bridge.generated")
                  (str/replace #"[^A-Za-z0-9_.:-]" "_")
                  (str/replace #"_+" "_")
                  (str/replace #"^_+" "")
                  (str/replace #"_+$" ""))]
    (if (str/blank? clean)
      "theorem.bridge.generated"
      clean)))

(defn render-theorem-bridge-module
  [{:keys [module-name contracts source-path]}]
  (let [contracts* (sort-by :id contracts)
        module* (sanitize-module-name module-name)]
    (str
     "MODULE " module* ".\n\n"
     "// Generated by `clojure -M -m zil.cli theorem-bridge`.\n"
     "// Source: " source-path "\n"
     "// This output contains formal sidecar skeletons from theorem contracts.\n\n"
     (str/join "\n\n" (map render-theorem-block contracts*))
     "\n")))

(defn theorem-contracts->bridge
  "Generate a ZIL formal sidecar module from theorem contracts found in path.

  Options:
  - :module-name override generated module name
  - :output-path write output text to file"
  ([path]
   (theorem-contracts->bridge path {}))
  ([path {:keys [module-name output-path]}]
   (let [files (bt/collect-zc-files path)]
     (when (empty? files)
       (throw (ex-info "No .zc files found in path for theorem bridge."
                       {:path path})))
    (let [results (mapv compile-file files)
          failed (vec (filter (complement :ok) results))]
       (when (seq failed)
         (throw (ex-info "Failed to parse .zc file for theorem bridge."
                         {:path path
                          :errors (mapv #(select-keys % [:file :error]) failed)})))
       (let [compiled (mapv :compiled results)
             modules (->> compiled (map :module) distinct vec)
             facts (mapcat :facts compiled)
             contracts (theorem-contracts-from-facts facts)]
         (when (empty? contracts)
           (throw (ex-info "No theorem contracts found in input path."
                           {:path path
                            :files files
                            :modules modules})))
         (let [module* (or module-name
                           (if (= 1 (count modules))
                             (str (first modules) ".theorem.bridge")
                             "theorem.bridge.generated"))
               text (render-theorem-bridge-module {:module-name module*
                                                   :contracts contracts
                                                   :source-path path})]
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
            :module module*
            :theorem_count (count contracts)
            :theorems (mapv :id contracts)
            :output_path output-path
            :text text}))))))
