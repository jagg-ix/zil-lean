(ns zil.bridge.lean4
  "Bridge helpers to export ZIL LTS_ATOM vocabularies to Lean4 skeletons."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.bridge.tla :as bt]))

(def ^:private lean-reserved
  #{"abbrev" "axiom" "class" "def" "deriving" "do" "else" "end" "example"
    "if" "import" "in" "inductive" "instance" "let" "match" "namespace"
    "open" "private" "protected" "set_option" "structure" "theorem" "variable"
    "where" "with"})

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
      "Item"
      (apply str (map pascalize-part parts)))))

(defn- to-lower-ident
  [s]
  (let [parts (tokenize-ident s)]
    (if (empty? parts)
      "item"
      (let [head (str/lower-case (first parts))
            tail (map pascalize-part (rest parts))]
        (apply str head tail)))))

(defn- sanitize-lean-ident
  [candidate fallback-prefix]
  (let [clean (str/replace candidate #"[^A-Za-z0-9_]" "_")
        with-prefix (if (re-matches #"^[0-9].*" clean)
                      (str fallback-prefix clean)
                      clean)
        safe (if (contains? lean-reserved with-prefix)
               (str with-prefix "_")
               with-prefix)]
    (if (str/blank? safe) (str fallback-prefix "item") safe)))

(defn- unique-ident-map
  [tokens base-fn fallback-prefix]
  (loop [remaining (vec tokens)
         used #{}
         out {}]
    (if (empty? remaining)
      out
      (let [token (first remaining)
            base (sanitize-lean-ident (base-fn token) fallback-prefix)
            candidate (loop [idx 1 cand base]
                        (if (contains? used cand)
                          (recur (inc idx) (str base "_" idx))
                          cand))]
        (recur (subvec remaining 1)
               (conj used candidate)
               (assoc out token candidate))))))

(defn- render-mapping-comment
  [title mapping]
  (str "/- " title " mapping (source -> Lean constructor)\n"
       (str/join "\n"
                 (for [[source ctor] mapping]
                   (str "- " source " -> " ctor)))
       "\n-/\n"))

(defn- render-inductive
  [type-name ctors]
  (str "inductive " type-name " where\n"
       (str/join "\n" (map #(str "  | " %) ctors))
       "\n  deriving DecidableEq, Repr\n"))

(defn- render-list
  [ctors]
  (if (empty? ctors)
    "[]"
    (str "[" (str/join ", " (map #(str "." %) ctors)) "]")))

(defn- render-actor-block
  [{:keys [actor-prefix states initial transitions trace-labels]}]
  (let [state-map (unique-ident-map states to-lower-ident "s")
        event-labels (->> transitions (map :label) distinct sort vec)
        event-map (unique-ident-map event-labels to-lower-ident "e")
        state-ctors (mapv state-map states)
        event-ctors (mapv event-map event-labels)
        initial-ctor (get state-map initial)
        step-name (str "step" actor-prefix)
        initial-name (str "initial" actor-prefix "State")
        trace-name (str actor-prefix "CanonicalTrace")
        rows (->> transitions
                  (map (fn [{:keys [from label to]}]
                         (str "  | ." (get state-map from) ", ." (get event-map label)
                              " => ." (get state-map to))))
                  vec)]
    (str
     "/-! ## " actor-prefix " -/\n\n"
     (render-mapping-comment (str actor-prefix "State") (into (sorted-map) state-map))
     (render-inductive (str actor-prefix "State") state-ctors) "\n"
     (render-mapping-comment (str actor-prefix "Event") (into (sorted-map) event-map))
     (render-inductive (str actor-prefix "Event") event-ctors) "\n"
     "def " initial-name " : " actor-prefix "State := ." initial-ctor "\n\n"
     "def " step-name " (s : " actor-prefix "State) (e : " actor-prefix "Event) : "
     actor-prefix "State :=\n"
     "  match s, e with\n"
     (str/join "\n" rows) "\n"
     "  | _, _ => s\n\n"
     "def " trace-name " : List " actor-prefix "Event := "
     (render-list (mapv event-map trace-labels)) "\n")))

(defn- module-token->segment
  [s]
  (-> s
      to-pascal-ident
      (sanitize-lean-ident "N")))

(defn- default-namespace
  [modules]
  (if (= 1 (count modules))
    (let [segments (->> (str/split (first modules) #"[._:-]+")
                        (remove str/blank?)
                        (map module-token->segment)
                        vec)]
      (str/join "." (concat ["Zil" "Generated"] segments)))
    "Zil.Generated"))

(defn- sanitize-namespace
  [ns-str]
  (let [segments (->> (str/split (or ns-str "") #"\.")
                      (remove str/blank?)
                      (map module-token->segment)
                      vec)]
    (if (empty? segments)
      "Zil.Generated"
      (str/join "." segments))))

(defn render-lean4-module
  "Render Lean4 skeleton source from normalized actors."
  [{:keys [namespace actors source-path]
    :or {namespace "Zil.Generated"}}]
  (let [ns* (sanitize-namespace namespace)]
    (str
     "/-\n"
     "Generated by `clojure -M -m zil.cli export-lean` from ZIL LTS_ATOM declarations.\n"
     "Source: " source-path "\n"
     "-/\n\n"
     "namespace " ns* "\n\n"
     (str/join "\n\n" (map render-actor-block (sort-by :actor-prefix actors)))
     "\n\nend " ns* "\n")))

(defn export-lts->lean4
  "Export LTS_ATOM declarations in .zc input to Lean4 skeleton text.

  Options:
  - :namespace    Lean namespace (default derived from input module)
  - :output-path  write generated Lean file (if omitted, only :text is returned)"
  ([path]
   (export-lts->lean4 path {}))
  ([path {:keys [namespace output-path]}]
   (let [{:keys [files modules actors]} (bt/collect-lts-vocabulary path)
         ns* (sanitize-namespace (or namespace (default-namespace modules)))
         text (render-lean4-module {:namespace ns*
                                    :actors actors
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
      :namespace ns*
      :actor_count (count actors)
      :actors (mapv #(select-keys % [:name :actor-prefix :actor-key :file]) actors)
      :output_path output-path
      :text text})))
