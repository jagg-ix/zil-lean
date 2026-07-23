(ns zil.port.conformance
  "Compare legacy Clojure and native Lean ZIL semantics."
  (:gen-class)
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as str]
            [zil.bridge.tuple-lean :as tuple-lean]
            [zil.core :as core]
            [zil.port.library :as library]
            [zil.relational-ir :as rir]))

(def default-command ["lake" "exe" "zil" "--"])
(def default-output "generated/zil/conformance.edn")
(def default-sections
  #{"module" "declaration" "fact" "rule" "closed" "query" "query-row"})

(defn- escape-line [value]
  (-> (str value)
      (str/replace "\\" "\\\\")
      (str/replace "\t" "\\t")
      (str/replace "\n" "\\n")
      (str/replace "\r" "\\r")))

(defn- escape-attr [value]
  (-> (str value)
      (str/replace "%" "%25")
      (str/replace ";" "%3B")
      (str/replace "=" "%3D")
      (str/replace ":" "%3A")
      (str/replace "\t" "%09")
      (str/replace "\n" "%0A")))

(defn- token-text [value]
  (cond
    (string? value) value
    (keyword? value) (if-let [ns (namespace value)]
                       (str ns ":" (name value))
                       (name value))
    (symbol? value) (str value)
    (nil? value) "value:nil"
    :else (str value)))

(defn- lean-name [value]
  (let [text (token-text value)]
    (if (str/starts-with? text "?")
      (subs text 1)
      (try
        (tuple-lean/term->lean-name text)
        (catch Exception _
          (let [clean (str/replace text #"[^A-Za-z0-9_.]" "_")]
            (if (re-matches #"^[0-9].*" clean) (str "n" clean) clean)))))))

(defn- split-words [value]
  (->> (str/split (str value) #"[_\-]+")
       (remove str/blank?)))

(defn- upper-first [value]
  (if (str/blank? value) ""
      (str (str/upper-case (subs value 0 1)) (subs value 1))))

(defn- lower-camel [value]
  (let [parts (vec (split-words value))]
    (if (empty? parts)
      "relation"
      (str (str/lower-case (first parts))
           (apply str (map #(upper-first (str/lower-case %)) (rest parts)))))))

(defn- relation-name [relation]
  (let [canonical (rir/canonical-relation relation)
        ns (or (namespace canonical) "zil")]
    (str ns "." (lower-camel (name canonical)))))

(defn- encode-term [value]
  (if (and (string? value) (str/starts-with? value "?"))
    (str "var:" (lean-name value))
    (str "node:" (lean-name value))))

(defn- encode-attr-value [value]
  (cond
    (and (string? value) (str/starts-with? value "?"))
    (str "v:" (escape-attr (lean-name value)))

    (integer? value) (str "i:" value)
    (number? value) (str "d:" (escape-attr value))
    (boolean? value) (str "b:" (str/lower-case (str value)))
    (or (keyword? value) (symbol? value))
    (str "n:" (escape-attr (lean-name value)))
    (string? value) (str "n:" (escape-attr (lean-name value)))
    (nil? value) "n:value.nil"
    :else (str "s:" (escape-attr (pr-str value)))))

(defn- encode-attrs [attrs]
  (->> attrs
       (map (fn [[key value]]
              (str (lean-name key) "=" (encode-attr-value value))))
       sort
       (str/join ";")))

(defn encode-relation
  "Encode one legacy fact/literal using native semantic field orientation."
  [{:keys [object relation subject attrs]}]
  (str/join "\t"
            ["rel"
             (encode-term object)
             (relation-name relation)
             (encode-term subject)
             (encode-attrs attrs)]))

(defn- userset-info [subject]
  (when (string? subject)
    (let [index (.lastIndexOf ^String subject "#")]
      (when (and (pos? index) (< index (dec (count subject))))
        (let [base (subs subject 0 index)
              selector (subs subject (inc index))]
          (when (re-matches #"[A-Za-z0-9_.:-]+" selector)
            {:base base :relation (keyword selector)}))))))

(defn- generated-userset-rule [outer inner attrs]
  {:name (str "userset-" (name outer) "-via-" (name inner))
   :if [{:object "?object" :relation outer :subject "?userset" :attrs attrs}
        {:object "?userset" :relation inner :subject "?subject" :attrs {}}]
   :then [{:object "?object" :relation outer :subject "?subject" :attrs attrs}]
   :stratum 0})

(defn- lower-usersets [compiled]
  (let [{:keys [facts pairs]}
        (reduce (fn [{:keys [facts pairs]} fact]
                  (if-let [{:keys [base relation]} (userset-info (:subject fact))]
                    {:facts (conj facts (assoc fact :subject base))
                     :pairs (conj pairs [(:relation fact) relation (:attrs fact)])}
                    {:facts (conj facts fact) :pairs pairs}))
                {:facts [] :pairs []}
                (:facts compiled))
        generated (->> pairs distinct
                       (mapv (fn [[outer inner attrs]]
                               (generated-userset-rule outer inner attrs))))]
    (-> compiled
        (assoc :facts facts)
        (update :rules into generated))))

(defn- literal-vars [literal]
  (->> (concat [(:object literal) (:subject literal)]
               (vals (:attrs literal)))
       (filter #(and (string? %) (str/starts-with? % "?")))
       (map lean-name)
       distinct))

(defn- rule-variables [rule]
  (->> (:if rule)
       (remove :neg?)
       (mapcat literal-vars)
       distinct
       sort))

(defn- encode-relations [relations]
  (->> relations
       (map #(escape-line (encode-relation %)))
       sort
       (str/join "|")))

(defn- encode-rule-lines [rule]
  (let [positive (remove :neg? (:if rule))
        negative (map #(dissoc % :neg?) (filter :neg? (:if rule)))
        variables (str/join "," (rule-variables rule))]
    (for [head (:then rule)]
      (str/join "\t"
                ["rule" variables "graphDerived"
                 (encode-relations positive)
                 (encode-relations negative)
                 (escape-line (encode-relation head))]))))

(defn- query-variables [query]
  (->> (:where query)
       (remove :neg?)
       (mapcat literal-vars)
       distinct
       sort))

(defn- encode-query [query]
  (let [positive (remove :neg? (:where query))
        negative (map #(dissoc % :neg?) (filter :neg? (:where query)))]
    (str/join "\t"
              ["query"
               (lean-name (:name query))
               (str/join "," (query-variables query))
               (str/join "," (map lean-name (:find query)))
               (encode-relations positive)
               (encode-relations negative)])))

(defn- encode-row [query row]
  (str/join ";"
            (map (fn [variable value]
                   (str (lean-name variable) "=" (encode-term value)))
                 (:find query)
                 row)))

(defn- declaration-entity [{:keys [kind name]}]
  (let [text (token-text name)]
    (if (or (str/includes? text ":") (str/includes? text "."))
      (lean-name text)
      (str (lower-camel (name kind)) "." (lean-name text)))))

(defn- declaration-kind [{:keys [kind]}]
  (-> kind name str/upper-case (str/replace "-" "_")))

(defn legacy-report
  "Compile and execute source with the Clojure runtime, then emit ZILC/1 text."
  [source]
  (let [compiled (-> (core/compile-program source) lower-usersets)
        executed (core/execute-compiled compiled)
        detail-lines
        (concat
         (for [declaration (:declarations compiled)]
           (str/join "\t" ["declaration"
                              (declaration-kind declaration)
                              (declaration-entity declaration)]))
         (for [fact (:facts compiled)]
           (str "fact\t" (escape-line (encode-relation fact))))
         (mapcat encode-rule-lines (:rules compiled))
         (for [fact (:facts executed)]
           (str "closed\t" (escape-line (encode-relation fact))))
         (for [query (:queries compiled)] (encode-query query))
         (mapcat
          (fn [query]
            (for [row (get-in executed [:queries (:name query) :rows] [])]
              (str/join "\t"
                        ["query-row" (lean-name (:name query))
                         (escape-line (encode-row query row))])))
          (:queries compiled)))
        module-name (lean-name (:module compiled))]
    (str "ZILC\t1\n"
         "module\t" module-name "\n"
         (when (seq detail-lines)
           (str (str/join "\n" (sort detail-lines)) "\n")))))

(defn legacy-expanded [source]
  (let [lines (core/expand-macros source)]
    (str (str/join "\n" lines) (when (seq lines) "\n"))))

(defn parse-report-sections [text]
  (reduce (fn [out line]
            (if (str/blank? line)
              out
              (let [section (first (str/split line #"\t" 2))]
                (update out section (fnil conj (sorted-set)) line))))
          (sorted-map)
          (str/split-lines (str text))))

(defn compare-reports
  ([legacy native] (compare-reports legacy native default-sections))
  ([legacy native sections]
   (let [left (parse-report-sections legacy)
         right (parse-report-sections native)
         differences
         (into (sorted-map)
               (keep (fn [section]
                       (let [l (get left section (sorted-set))
                             r (get right section (sorted-set))
                             legacy-only (vec (set/difference l r))
                             native-only (vec (set/difference r l))]
                         (when (or (seq legacy-only) (seq native-only))
                           [section {:legacy-only legacy-only
                                     :native-only native-only}]))))
               (sort sections))]
     {:ok (empty? differences)
      :sections (vec (sort sections))
      :differences differences})))

(defn- native-run [runner command operation source-path]
  (runner (into (vec command) [operation source-path])))

(defn compare-file
  [{:keys [runner command sections]
    :or {runner library/run-command
         command default-command
         sections default-sections}}
   source-file]
  (let [path (.getCanonicalPath (io/file source-file))
        source (slurp path)
        legacy-result (try
                        {:ok true
                         :report (legacy-report source)
                         :expanded (legacy-expanded source)}
                        (catch Exception error
                          {:ok false
                           :error (.getMessage error)
                           :data (ex-data error)}))
        native-report (native-run runner command "conformance" path)
        native-expand (native-run runner command "expand" path)
        native-ok (zero? (:exit native-report))]
    (cond
      (and (not (:ok legacy-result)) (not native-ok))
      (sorted-map :source path
                  :source-sha256 (library/file-sha256 source-file)
                  :status :both-rejected
                  :ok true
                  :legacy-error (:error legacy-result)
                  :native-error (str/trim (:err native-report)))

      (not (:ok legacy-result))
      (sorted-map :source path
                  :source-sha256 (library/file-sha256 source-file)
                  :status :legacy-rejected
                  :ok false
                  :legacy-error (:error legacy-result))

      (not native-ok)
      (sorted-map :source path
                  :source-sha256 (library/file-sha256 source-file)
                  :status :native-rejected
                  :ok false
                  :native-error (str/trim (:err native-report)))

      :else
      (let [comparison (compare-reports (:report legacy-result)
                                        (:out native-report)
                                        sections)
            expansion-equal (and (zero? (:exit native-expand))
                                 (= (:expanded legacy-result) (:out native-expand)))
            ok (and (:ok comparison) expansion-equal)]
        (sorted-map :source path
                    :source-sha256 (library/file-sha256 source-file)
                    :status (if ok :pass :mismatch)
                    :ok ok
                    :sections (:sections comparison)
                    :differences (:differences comparison)
                    :expansion-equal expansion-equal
                    :native-expansion-error (when-not (zero? (:exit native-expand))
                                              (str/trim (:err native-expand))))))))

(defn- write-report! [path report]
  (let [file (io/file path)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file (str (pr-str report) "\n"))))

(defn run-suite!
  [{:keys [roots output sections]
    :or {roots library/default-roots
         output default-output
         sections default-sections}
    :as options}]
  (let [entries (mapv #(compare-file (assoc options :sections sections) (.toFile %))
                      (library/source-files roots))
        report (sorted-map
                :schema "ZIL-CONFORMANCE/1"
                :roots (mapv #(.getCanonicalPath (io/file %)) roots)
                :sections (vec (sort sections))
                :ok (every? :ok entries)
                :entries entries)]
    (write-report! output report)
    report))

(def usage
  "zil-conformance [--root DIR]* [--output FILE]")

(defn- parse-cli [args]
  (loop [remaining (seq args)
         options {:roots [] :output default-output}]
    (if-not remaining
      (update options :roots #(if (seq %) % library/default-roots))
      (let [arg (first remaining)]
        (case arg
          "--root" (recur (nnext remaining)
                          (update options :roots conj (second remaining)))
          "--output" (recur (nnext remaining)
                            (assoc options :output (second remaining)))
          "--help" (assoc options :help true)
          (throw (ex-info "Unknown conformance option" {:option arg})))))))

(defn -main [& args]
  (try
    (let [options (parse-cli args)]
      (if (:help options)
        (do (println usage) (System/exit 0))
        (let [report (run-suite! options)]
          (println (pr-str (select-keys report [:schema :ok :sections])))
          (System/exit (if (:ok report) 0 1)))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)] (prn data)))
      (System/exit 2))))
