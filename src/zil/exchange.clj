(ns zil.exchange
  "Revisioned exchange envelope shared with the Lean implementation."
  (:require [clojure.string :as str]
            [zil.relational-ir :as ir]))

(def schema-version "1")

(defn- encode-name [x]
  (cond
    (keyword? x) (if-let [ns (namespace x)] (str ns "." (name x)) (name x))
    (symbol? x) (str x)
    :else (str x)))

(defn- encode-term [{:term/keys [kind name value]}]
  (case kind
    :var (str "var:" name)
    :node (str "node:" (encode-name value))
    (throw (ex-info "Unknown canonical term kind" {:kind kind}))))

(defn encode-relation [relation]
  (str/join "\t" ["rel"
                    (encode-term (:subject relation))
                    (encode-name (:relation relation))
                    (encode-term (:object relation))]))

(defn- parse-name [s]
  (let [parts (str/split s #"\.")]
    (if (> (count parts) 1)
      (keyword (str/join "." (butlast parts)) (last parts))
      (keyword s))))

(defn- decode-term [s]
  (cond
    (str/starts-with? s "var:") {:term/kind :var :term/name (subs s 4)}
    (str/starts-with? s "node:") {:term/kind :node :term/value (subs s 5)}
    :else (throw (ex-info "Invalid canonical term" {:term s}))))

(defn decode-relation [text]
  (let [[tag subject relation object & extra] (str/split text #"\t" -1)]
    (when (or (not= tag "rel") (nil? object) (seq extra))
      (throw (ex-info "Invalid canonical relation" {:text text})))
    {:ir/kind :relation
     :subject (decode-term subject)
     :relation (parse-name relation)
     :object (decode-term object)}))

(defn- trust-name [trust]
  (case trust
    :asserted "asserted"
    :graph-derived "graphDerived"
    :certified "certified"
    "graphDerived"))

(defn- decode-trust [s]
  (case s
    "asserted" :asserted
    "graphDerived" :graph-derived
    "certified" :certified
    (throw (ex-info "Invalid trust class" {:trust s}))))

(defn encode-rule [rule]
  (let [header (str/join "\t" ["rule" (:rule/name rule)
                                 (str/join "," (:rule/variables rule))
                                 (trust-name (:rule/trust rule))])
        premises (map #(str "premise\t" (encode-relation %)) (:rule/premises rule))
        conclusion (str "conclusion\t" (encode-relation (:rule/conclusion rule)))]
    (str/join "\n" (concat [header] premises [conclusion]))))

(defn decode-rule [text]
  (let [[header & rows] (str/split-lines text)
        [tag rule-name variables trust & extra] (str/split header #"\t" -1)]
    (when (or (not= tag "rule") (nil? trust) (seq extra))
      (throw (ex-info "Invalid canonical rule header" {:text text})))
    (let [premises (->> rows
                        (filter #(str/starts-with? % "premise\t"))
                        (mapv #(decode-relation (subs % 8))))
          conclusions (->> rows
                           (filter #(str/starts-with? % "conclusion\t"))
                           (mapv #(decode-relation (subs % 11))))]
      (when-not (= 1 (count conclusions))
        (throw (ex-info "Canonical rule requires exactly one conclusion"
                        {:count (count conclusions)})))
      {:ir/kind :rule
       :rule/name rule-name
       :rule/variables (if (str/blank? variables) [] (str/split variables #","))
       :rule/premises premises
       :rule/conclusion (first conclusions)
       :rule/trust (decode-trust trust)})))

(defn- escape-field [s]
  (-> (str s)
      (str/replace "\\" "\\\\")
      (str/replace "\n" "\\n")
      (str/replace "\t" "\\t")))

(defn- unescape-field [s]
  (loop [chars (seq s) out (StringBuilder.)]
    (if-let [c (first chars)]
      (if (= c \\)
        (let [n (second chars)]
          (case n
            \n (recur (nnext chars) (.append out \newline))
            \t (recur (nnext chars) (.append out \tab))
            \\ (recur (nnext chars) (.append out \\))
            (recur (next chars) (.append out c))))
        (recur (next chars) (.append out c)))
      (str out))))

(defn encode-envelope [{:keys [knowledge-revision profile-name profile-version facts rules]
                        :or {knowledge-revision 0 facts [] rules []}}]
  (str/join "\n"
            (concat [(str "ZILX\t" schema-version)
                     (str "revision\t" knowledge-revision)
                     (str "profile\t" (if profile-name (escape-field profile-name) "-")
                          "\t" (if profile-version (escape-field profile-version) "-"))]
                    (map #(str "fact\t" (escape-field (encode-relation %))) facts)
                    (map #(str "rule\t" (escape-field (encode-rule %))) rules))))

(defn decode-envelope [text]
  (let [[header revision profile & rows] (str/split-lines text)
        [header-tag version] (str/split header #"\t" -1)
        [revision-tag revision-value] (str/split revision #"\t" -1)
        [profile-tag profile-name profile-version] (str/split profile #"\t" -1)]
    (when-not (and (= header-tag "ZILX") (= revision-tag "revision")
                   (= profile-tag "profile"))
      (throw (ex-info "Invalid ZILX envelope header" {:text text})))
    (reduce (fn [envelope row]
              (let [[tag payload & extra] (str/split row #"\t" -1)]
                (when (or (nil? payload) (seq extra))
                  (throw (ex-info "Malformed exchange row" {:row row})))
                (case tag
                  "fact" (update envelope :facts conj (decode-relation (unescape-field payload)))
                  "rule" (update envelope :rules conj (decode-rule (unescape-field payload)))
                  (throw (ex-info "Unknown exchange row" {:tag tag})))))
            {:schema-version version
             :knowledge-revision (Long/parseLong revision-value)
             :profile-name (when-not (= profile-name "-") (unescape-field profile-name))
             :profile-version (when-not (= profile-version "-") (unescape-field profile-version))
             :facts [] :rules []}
            rows)))

(defn semantic-envelope-view [envelope]
  (-> envelope
      (update :facts #(mapv ir/semantic-view %))
      (update :rules #(mapv (fn [rule]
                              (select-keys rule [:ir/kind :rule/name :rule/variables
                                                 :rule/premises :rule/conclusion :rule/trust])) %))))

(defn round-trips? [envelope]
  (= (semantic-envelope-view envelope)
     (semantic-envelope-view (decode-envelope (encode-envelope envelope)))))