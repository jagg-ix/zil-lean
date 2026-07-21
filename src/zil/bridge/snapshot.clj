(ns zil.bridge.snapshot
  "Deterministic, validated ZIL snapshots for offline Lean consumption."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core])
  (:import [java.nio.charset StandardCharsets]
           [java.nio.file Files StandardCopyOption]
           [java.security MessageDigest]))

(def format-version "zil.snapshot.v0.2")

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes text StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and % 0xff)) digest))))

(defn- variable-token? [value]
  (and (string? value) (str/starts-with? value "?") (> (count value) 1)))

(defn- value-map [value]
  (cond
    (variable-token? value) (sorted-map "var" (subs value 1))
    (string? value) (sorted-map "symbol" value)
    (keyword? value) (sorted-map "symbol" (name value))
    (integer? value) (sorted-map "integer" value)
    (boolean? value) (sorted-map "boolean" value)
    :else (throw (ex-info "Unsupported snapshot scalar"
                          {:code :unsupported-format :value value}))))

(defn- attrs-map [attrs]
  (->> attrs
       (sort-by (comp name key))
       (mapv (fn [[key value]]
               (sorted-map "key" (name key) "term" (value-map value))))))

(defn- atom-map [atom context]
  (try
    (sorted-map "attrs" (attrs-map (:attrs atom))
              "object" (value-map (:object atom))
              "relation" (name (:relation atom))
              "subject" (value-map (:subject atom)))
    (catch clojure.lang.ExceptionInfo error
      (throw (ex-info "Snapshot atom contains a value outside the native Lean scalar core"
                      {:code :unsupported-format :context context :atom atom}
                      error)))))

(defn- literal-map [literal context]
  (sorted-map "atom" (atom-map literal context)
              "polarity" (if (:neg? literal) "negative" "positive")))

(defn- rule-map [rule]
  (when (not= 1 (count (:then rule)))
    (throw (ex-info "Snapshot v0.1 requires exactly one rule head"
                    {:code :unsupported-format :rule (:name rule)
                     :head-count (count (:then rule))})))
  (sorted-map "head" (atom-map (first (:then rule)) [:rule (:name rule) :head])
              "literals" (mapv #(literal-map % [:rule (:name rule) :body]) (:if rule))
              "name" (:name rule)))

(defn compile-snapshot [path]
  (let [source (slurp path)
        source-hash (sha256 source)
        compiled (core/compile-program source)]
    (sorted-map
     "completeness" "complete"
     "facts" (->> (:facts compiled) (map #(atom-map % :fact)) (sort-by pr-str) vec)
     "format" format-version
     "module" (:module compiled)
     "profile" "stratified-attributes-v0.2"
     "revision" (str "sha256:" source-hash)
     "rules" (->> (:rules compiled) (map rule-map) (sort-by #(get % "name")) vec)
     "source" (.getCanonicalPath (io/file path))
     "source_sha256" source-hash
     "trust" (sorted-map "external_evidence_is_proof" false
                         "lean_kernel_required_for_proved" true))))

(defn render-json [snapshot]
  (str (json/write-str snapshot :escape-slash false) "\n"))

(defn- lean-string [value] (pr-str (str value)))

(defn- lean-term [term]
  (let [[kind value] (first term)]
    (case kind
      "var" (str ".variable " (lean-string value))
      "symbol" (str ".value (.symbol " (lean-string value) ")")
      "string" (str ".value (.string " (lean-string value) ")")
      "integer" (str ".value (.integer " value ")")
      "boolean" (str ".value (.boolean " value ")")
      (throw (ex-info "Unsupported term tag" {:term term})))))

(defn- lean-value [term]
  (let [rendered (lean-term term)]
    (if (str/starts-with? rendered ".value ")
      (subs rendered (count ".value "))
      (throw (ex-info "Variables are invalid in ground facts" {:term term})))))

(defn- lean-pattern [atom]
  (str "{ object := " (lean-term (get atom "object"))
       ", relation := " (lean-string (get atom "relation"))
       ", subject := " (lean-term (get atom "subject"))
       ", attrs := ["
       (str/join ", " (map #(str "(" (lean-string (get % "key")) ", "
                                  (lean-term (get % "term")) ")")
                            (get atom "attrs"))) "] }"))

(defn- lean-atom [atom]
  (str "{ object := " (lean-value (get atom "object"))
       ", relation := " (lean-string (get atom "relation"))
       ", subject := " (lean-value (get atom "subject"))
       ", attrs := ["
       (str/join ", " (map #(str "(" (lean-string (get % "key")) ", "
                                  (lean-value (get % "term")) ")")
                            (get atom "attrs"))) "] }"))

(defn- lean-literal [literal]
  (str "." (get literal "polarity") " " (lean-pattern (get literal "atom"))))

(defn- lean-rule [rule]
  (str "{ name := " (lean-string (get rule "name"))
       ", head := " (lean-pattern (get rule "head"))
       ", literals := ["
       (str/join ", " (map lean-literal (get rule "literals")))
       "] }"))

(defn- zil-lean-term [term]
  (let [[kind value] (first term)]
    (case kind
      "var" (str "?" value)
      "symbol" (lean-string value)
      "string" (lean-string value)
      "integer" (str value)
      "boolean" (str value)
      (throw (ex-info "Unsupported embedded term tag" {:term term})))))

(defn- zil-lean-atom [atom]
  (str (zil-lean-term (get atom "object")) " # " (get atom "relation") " @ "
       (zil-lean-term (get atom "subject"))
       (when (seq (get atom "attrs"))
         (str " [" (str/join ", "
                    (map #(str (get % "key") " = " (zil-lean-term (get % "term")))
                         (get atom "attrs"))) "]"))))

(defn- zil-lean-literal [literal]
  (str (when (= "negative" (get literal "polarity")) "NOT ")
       (zil-lean-atom (get literal "atom"))))

(defn- zil-lean-rule [rule]
  (str "zil_rule " (get rule "name") ":\n  "
       (zil-lean-atom (get rule "head")) " IF\n  "
       (str/join " AND\n  " (map zil-lean-literal (get rule "literals")))))

(defn render-lean
  ([snapshot] (render-lean snapshot "Zil.Generated.Snapshot"))
  ([snapshot namespace]
   (str "-- Generated from an immutable ZIL snapshot. Do not edit.\n"
        "module\n\npublic import Zil\n\n@[expose] public section\n\nnamespace "
        namespace "\n\nopen Zil\n\n"
        "zil_snapshot " (lean-string (get snapshot "revision"))
        " completeness " (get snapshot "completeness") "\n\n"
        (str/join "\n" (map #(str "zil_fact " (zil-lean-atom %))
                              (get snapshot "facts")))
        "\n\n"
        (str/join "\n\n" (map zil-lean-rule (get snapshot "rules")))
        "\n\n"
        "def snapshotRevision : String := " (lean-string (get snapshot "revision")) "\n"
        "def snapshotSourceSha256 : String := " (lean-string (get snapshot "source_sha256")) "\n"
        "def snapshotCompleteness : String := " (lean-string (get snapshot "completeness")) "\n\n"
        "def program : Program := {\n  facts := ["
        (str/join ",\n    " (map lean-atom (get snapshot "facts")))
        "],\n  rules := ["
        (str/join ",\n    " (map lean-rule (get snapshot "rules")))
        "]\n}\n\nend " namespace "\n")))

(defn- atomic-spit! [path text]
  (let [target (.toPath (io/file path))
        parent (.getParent target)]
    (when parent (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0)))
    (let [tmp (Files/createTempFile parent ".zil-snapshot-" ".tmp"
                                    (make-array java.nio.file.attribute.FileAttribute 0))]
      (spit (.toFile tmp) text)
      (Files/move tmp target
                  (into-array StandardCopyOption
                              [StandardCopyOption/ATOMIC_MOVE
                               StandardCopyOption/REPLACE_EXISTING])))))

(defn export-snapshot! [path {:keys [json-output lean-output namespace]
                              :or {namespace "Zil.Generated.Snapshot"}}]
  (let [snapshot (compile-snapshot path)]
    (when json-output (atomic-spit! json-output (render-json snapshot)))
    (when lean-output (atomic-spit! lean-output (render-lean snapshot namespace)))
    {:ok true
     :revision (get snapshot "revision")
     :completeness (get snapshot "completeness")
     :fact_count (count (get snapshot "facts"))
     :rule_count (count (get snapshot "rules"))
     :json_output json-output
     :lean_output lean-output
     :snapshot snapshot}))
