(ns zil.bridge.vstack
  "Bridge helpers to generate refinement-relation sidecar skeletons from
   REFINES/CORRESPONDS/PROOF_OBLIGATION declarations.

   Output is a generated .zc module with:
   - one LTS_ATOM skeleton per REFINES declaration
   - one LTS_ATOM skeleton per CORRESPONDS declaration
   - one LTS_ATOM + one POLICY skeleton per PROOF_OBLIGATION declaration."
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
      "Entity"
      (apply str (map pascalize-part parts)))))

(defn- unprefix
  [prefix s]
  (let [txt (token->name s)]
    (if (str/starts-with? txt prefix)
      (subs txt (count prefix))
      txt)))

(defn- value-token->text
  [v]
  (unprefix "value:" (token->name v)))

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

(defn- entity-objects
  [facts kind]
  (let [kind-token (str "entity:" (name kind))
        prefix (str (name kind) ":")]
    (->> facts
         (filter (fn [{:keys [object relation subject]}]
                   (and (= :kind relation)
                        (= kind-token (token->name subject))
                        (string? object)
                        (str/starts-with? object prefix))))
         (map :object)
         distinct
         sort
         vec)))

(defn- rel-values
  [facts rel]
  (->> facts
       (filter #(= rel (:relation %)))
       (map (comp token->name :subject))
       distinct
       sort
       vec))

(defn- first-rel-value
  [facts rel]
  (some-> (first (rel-values facts rel)) value-token->text))

(defn- criticality-token
  [facts]
  (let [raw (some-> (first (rel-values facts :criticality))
                    value-token->text
                    str/lower-case)
        allowed #{"low" "medium" "high" "critical"}]
    (if (contains? allowed raw) raw "medium")))

(defn- refines-contracts-from-facts
  [facts]
  (let [by-object (group-by :object facts)
        objs (entity-objects facts :refines)]
    (mapv
     (fn [obj]
       (let [id (unprefix "refines:" obj)
             fs (get by-object obj [])]
         {:id id
          :spec (first-rel-value fs :spec)
          :impl (first-rel-value fs :impl)
          :mapping (first-rel-value fs :mapping)
          :layer_from (or (first-rel-value fs :layer_from) "spec")
          :layer_to (or (first-rel-value fs :layer_to) "logic")}))
     objs)))

(defn- corresponds-contracts-from-facts
  [facts]
  (let [by-object (group-by :object facts)
        objs (entity-objects facts :corresponds)]
    (mapv
     (fn [obj]
       (let [id (unprefix "corresponds:" obj)
             fs (get by-object obj [])]
         {:id id
          :left (first-rel-value fs :left)
          :right (first-rel-value fs :right)
          :domain (first-rel-value fs :domain)
          :refines (vec (map value-token->text (rel-values fs :refines)))}))
     objs)))

(defn- proof-obligation-contracts-from-facts
  [facts]
  (let [by-object (group-by :object facts)
        objs (entity-objects facts :proof_obligation)]
    (mapv
     (fn [obj]
       (let [id (unprefix "proof_obligation:" obj)
             fs (get by-object obj [])]
         {:id id
          :relations (vec (map value-token->text (rel-values fs :relation)))
          :statement (or (first-rel-value fs :statement) "")
          :tool (or (first-rel-value fs :tool) "manual")
          :criticality (criticality-token fs)}))
     objs)))

(defn- relation-proof-vars
  [refs]
  (if (empty? refs)
    "true"
    (str/join " AND "
              (map (fn [ref]
                     (str "rel_" (safe-var ref) "_valid"))
                   refs))))

(defn- render-refines-block
  [{:keys [id spec impl mapping layer_from layer_to]}]
  (let [sid (safe-ident id)
        actor (safe-ident (str "Refines" (to-pascal-ident id)))
        actor-key (safe-ident (str "refines" (to-pascal-ident id)))
        lts-name (safe-ident (str "refines_" sid "_flow"))
        ref-var (str "refines_" (safe-var sid) "_holds")
        map-var (str "mapping_" (safe-var sid) "_preserved")
        policy-name (safe-ident (str "refines_" sid "_soundness"))
        soundness (str ref-var " IMPLIES " map-var)]
    (str
     "// refines: " id "\n"
     (when spec (str "// spec: " spec "\n"))
     (when impl (str "// impl: " impl "\n"))
     (when mapping (str "// mapping: " mapping "\n"))
     "// layers: " layer_from " -> " layer_to "\n"
     "LTS_ATOM " lts-name
     " [actor=" actor
     ", actor_key=" actor-key
     ", states=#{declared mapped validated violated}"
     ", initial=declared"
     ", transitions={[declared map_relation] [mapped],"
     " [mapped validate_relation] [validated],"
     " [validated witness_drift] [violated],"
     " [violated repair_mapping] [mapped]}].\n"
     "POLICY " policy-name " [condition=\"" soundness "\", criticality=high].\n")))

(defn- render-corresponds-block
  [{:keys [id left right domain refines]}]
  (let [sid (safe-ident id)
        actor (safe-ident (str "Corresponds" (to-pascal-ident id)))
        actor-key (safe-ident (str "corresponds" (to-pascal-ident id)))
        lts-name (safe-ident (str "corresponds_" sid "_flow"))
        corr-var (str "corresponds_" (safe-var sid) "_holds")
        witness-var (str "correspondence_" (safe-var sid) "_witnessed")
        policy-name (safe-ident (str "corresponds_" sid "_soundness"))
        soundness (str corr-var " IMPLIES " witness-var)]
    (str
     "// corresponds: " id "\n"
     (when left (str "// left: " left "\n"))
     (when right (str "// right: " right "\n"))
     (when domain (str "// domain: " domain "\n"))
     (when (seq refines)
       (str "// linked refines: " (str/join ", " refines) "\n"))
     "LTS_ATOM " lts-name
     " [actor=" actor
     ", actor_key=" actor-key
     ", states=#{declared checked aligned diverged}"
     ", initial=declared"
     ", transitions={[declared check_correspondence] [checked],"
     " [checked establish_alignment] [aligned],"
     " [aligned observe_divergence] [diverged],"
     " [diverged realign] [checked]}].\n"
     "POLICY " policy-name " [condition=\"" soundness "\", criticality=high].\n")))

(defn- render-proof-obligation-block
  [{:keys [id relations statement tool criticality]}]
  (let [sid (safe-ident id)
        actor (safe-ident (str "ProofObligation" (to-pascal-ident id)))
        actor-key (safe-ident (str "proofObligation" (to-pascal-ident id)))
        lts-name (safe-ident (str "proof_obligation_" sid "_flow"))
        policy-name (safe-ident (str "proof_obligation_" sid "_soundness"))
        obligation-var (str "proof_obligation_" (safe-var sid) "_proved")
        relation-guard (relation-proof-vars relations)
        soundness (str obligation-var " IMPLIES (" relation-guard ")")]
    (str
     "// proof obligation: " id "\n"
     (when (seq relations)
       (str "// relation targets: " (str/join ", " relations) "\n"))
     (when-not (str/blank? statement)
       (str "// statement: " statement "\n"))
     "// tool: " tool "\n"
     "LTS_ATOM " lts-name
     " [actor=" actor
     ", actor_key=" actor-key
     ", states=#{open pending proved failed waived}"
     ", initial=open"
     ", transitions={[open start_check] [pending],"
     " [pending discharge] [proved],"
     " [pending counterexample] [failed],"
     " [failed reopen] [pending],"
     " [failed waive] [waived]}].\n"
     "POLICY " policy-name " [condition=\"" soundness "\", criticality=" criticality "].\n")))

(defn- sanitize-module-name
  [s]
  (let [clean (-> (or s "vstack.bridge.generated")
                  (str/replace #"[^A-Za-z0-9_.:-]" "_")
                  (str/replace #"_+" "_")
                  (str/replace #"^_+" "")
                  (str/replace #"_+$" ""))]
    (if (str/blank? clean)
      "vstack.bridge.generated"
      clean)))

(defn render-vstack-bridge-module
  [{:keys [module-name source-path refines corresponds proof-obligations]}]
  (let [module* (sanitize-module-name module-name)
        refines* (sort-by :id refines)
        corresponds* (sort-by :id corresponds)
        obligations* (sort-by :id proof-obligations)
        blocks (concat (map render-refines-block refines*)
                       (map render-corresponds-block corresponds*)
                       (map render-proof-obligation-block obligations*))]
    (str
     "MODULE " module* ".\n\n"
     "// Generated by `clojure -M -m zil.cli vstack-ci` refinement bridge stage.\n"
     "// Source: " source-path "\n"
     "// This output contains formal sidecar skeletons for the V-Stack refinement relation layer.\n\n"
     (str/join "\n\n" blocks)
     "\n")))

(defn refinement-contracts->bridge
  "Generate a ZIL formal sidecar module from refinement contracts found in path.

  Options:
  - :module-name override generated module name
  - :output-path write output text to file"
  ([path]
   (refinement-contracts->bridge path {}))
  ([path {:keys [module-name output-path]}]
   (let [files (bt/collect-zc-files path)]
     (when (empty? files)
       (throw (ex-info "No .zc files found in path for vstack bridge."
                       {:path path})))
     (let [results (mapv compile-file files)
           failed (vec (filter (complement :ok) results))]
       (when (seq failed)
         (throw (ex-info "Failed to parse .zc file for vstack bridge."
                         {:path path
                          :errors (mapv #(select-keys % [:file :error]) failed)})))
       (let [compiled (mapv :compiled results)
             modules (->> compiled (map :module) distinct vec)
             facts (mapcat :facts compiled)
             refines (refines-contracts-from-facts facts)
             corresponds (corresponds-contracts-from-facts facts)
             proof-obligations (proof-obligation-contracts-from-facts facts)]
         (when (and (empty? refines)
                    (empty? corresponds)
                    (empty? proof-obligations))
           (throw (ex-info "No refinement relation declarations found in input path."
                           {:path path
                            :files files
                            :modules modules})))
         (let [module* (or module-name
                           (if (= 1 (count modules))
                             (str (first modules) ".vstack.bridge")
                             "vstack.bridge.generated"))
               text (render-vstack-bridge-module {:module-name module*
                                                  :source-path path
                                                  :refines refines
                                                  :corresponds corresponds
                                                  :proof-obligations proof-obligations})]
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
            :refines_count (count refines)
            :corresponds_count (count corresponds)
            :proof_obligation_count (count proof-obligations)
            :refines (mapv :id refines)
            :corresponds (mapv :id corresponds)
            :proof_obligations (mapv :id proof-obligations)
            :output_path output-path
            :text text}))))))
