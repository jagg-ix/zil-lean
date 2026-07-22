(ns zil.delta
  "Revision-checked incremental updates for ZILX exchange snapshots."
  (:require [clojure.string :as str]
            [zil.exchange :as exchange]
            [zil.relational-ir :as ir]))

(defn- relation=? [left right]
  (ir/equivalent? left right))

(defn- remove-fact [facts target]
  (if (some #(relation=? % target) facts)
    (vec (remove #(relation=? % target) facts))
    (throw (ex-info "Delta removes a missing fact" {:fact target}))))

(defn- add-fact [facts fact]
  (if (some #(relation=? % fact) facts) facts (conj facts fact)))

(defn- rule-name [rule] (:rule/name rule))

(defn- remove-rule [rules name]
  (if (some #(= name (rule-name %)) rules)
    (vec (remove #(= name (rule-name %)) rules))
    (throw (ex-info "Delta removes a missing rule" {:rule name}))))

(defn- add-rule [rules rule]
  (if (some #(= (rule-name rule) (rule-name %)) rules)
    (mapv #(if (= (rule-name rule) (rule-name %)) rule %) rules)
    (conj rules rule)))

(defn apply-delta [snapshot {:keys [base-revision target-revision add-facts remove-facts
                                    add-rules remove-rules profile-name profile-version]
                             :or {add-facts [] remove-facts [] add-rules [] remove-rules []}}]
  (let [actual (:knowledge-revision snapshot)]
    (when-not (= base-revision actual)
      (throw (ex-info "Stale knowledge revision"
                      {:expected actual :actual base-revision})))
    (when-not (> target-revision base-revision)
      (throw (ex-info "Target revision must increase"
                      {:base base-revision :target target-revision})))
    (-> snapshot
        (assoc :knowledge-revision target-revision)
        (update :facts #(reduce remove-fact (vec %) remove-facts))
        (update :facts #(reduce add-fact (vec %) add-facts))
        (update :rules #(reduce remove-rule (vec %) remove-rules))
        (update :rules #(reduce add-rule (vec %) add-rules))
        (cond-> profile-name (assoc :profile-name profile-name)
                profile-version (assoc :profile-version profile-version)))))

(defn compose-delta [first second]
  (when-not (= (:target-revision first) (:base-revision second))
    (throw (ex-info "Deltas are not adjacent"
                    {:expected (:target-revision first)
                     :actual (:base-revision second)})))
  {:base-revision (:base-revision first)
   :target-revision (:target-revision second)
   :add-facts (vec (concat (:add-facts first) (:add-facts second)))
   :remove-facts (vec (concat (:remove-facts first) (:remove-facts second)))
   :add-rules (vec (concat (:add-rules first) (:add-rules second)))
   :remove-rules (vec (concat (:remove-rules first) (:remove-rules second)))
   :profile-name (or (:profile-name second) (:profile-name first))
   :profile-version (or (:profile-version second) (:profile-version first))})

(defn- escape-field [s]
  (-> (str s)
      (str/replace "\\" "\\\\")
      (str/replace "\n" "\\n")
      (str/replace "\t" "\\t")))

(defn- unescape-field [s]
  (loop [chars (seq s) out (StringBuilder.)]
    (if-let [c (first chars)]
      (if (= c \\)
        (case (second chars)
          \n (recur (nnext chars) (.append out \newline))
          \t (recur (nnext chars) (.append out \tab))
          \\ (recur (nnext chars) (.append out \\))
          (recur (next chars) (.append out c)))
        (recur (next chars) (.append out c)))
      (str out))))

(defn encode-delta [{:keys [base-revision target-revision add-facts remove-facts
                            add-rules remove-rules profile-name profile-version]
                     :or {add-facts [] remove-facts [] add-rules [] remove-rules []}}]
  (str/join "\n"
            (concat [(str "ZILD\t1")
                     (str "base\t" base-revision)
                     (str "target\t" target-revision)
                     (str "profile\t" (or profile-name "-") "\t" (or profile-version "-"))]
                    (map #(str "add-fact\t" (escape-field (exchange/encode-relation %))) add-facts)
                    (map #(str "remove-fact\t" (escape-field (exchange/encode-relation %))) remove-facts)
                    (map #(str "add-rule\t" (escape-field (exchange/encode-rule %))) add-rules)
                    (map #(str "remove-rule\t" %) remove-rules))))

(defn decode-delta [text]
  (let [[header base target profile & rows] (str/split-lines text)
        [base-tag base-value] (str/split base #"\t" -1)
        [target-tag target-value] (str/split target #"\t" -1)
        [profile-tag profile-name profile-version] (str/split profile #"\t" -1)]
    (when-not (and (= header "ZILD\t1") (= base-tag "base")
                   (= target-tag "target") (= profile-tag "profile"))
      (throw (ex-info "Invalid ZILD metadata" {:text text})))
    (reduce (fn [delta row]
              (let [[tag payload & extra] (str/split row #"\t" -1)]
                (when (or (nil? payload) (seq extra))
                  (throw (ex-info "Malformed delta row" {:row row})))
                (case tag
                  "add-fact" (update delta :add-facts conj
                                     (exchange/decode-relation (unescape-field payload)))
                  "remove-fact" (update delta :remove-facts conj
                                        (exchange/decode-relation (unescape-field payload)))
                  "add-rule" (update delta :add-rules conj
                                     (exchange/decode-rule (unescape-field payload)))
                  "remove-rule" (update delta :remove-rules conj payload)
                  (throw (ex-info "Unknown delta row" {:tag tag})))))
            {:base-revision (Long/parseLong base-value)
             :target-revision (Long/parseLong target-value)
             :profile-name (when-not (= profile-name "-") profile-name)
             :profile-version (when-not (= profile-version "-") profile-version)
             :add-facts [] :remove-facts [] :add-rules [] :remove-rules []}
            rows)))