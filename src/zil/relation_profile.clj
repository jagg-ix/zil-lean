(ns zil.relation-profile
  "Versioned domain/range validation for canonical relational IR."
  (:require [clojure.string :as str]))

(def node-kinds
  #{:declaration :claim :requirement :evidence-source :concept :file :theorem})

(defn infer-ground-kind
  "Infer a semantic kind from a stable ground-node namespace."
  [name]
  (let [text (str name)]
    (cond
      (str/starts-with? text "claim.") :claim
      (str/starts-with? text "requirement.") :requirement
      (or (str/starts-with? text "paper.")
          (str/starts-with? text "source.")) :evidence-source
      (str/starts-with? text "concept.") :concept
      (str/starts-with? text "file.") :file
      (str/starts-with? text "theorem.") :theorem
      (str/starts-with? text "lean.") :declaration
      :else nil)))

(def research-profile
  {:profile/name :zil.profile/research
   :profile/version "0.1"
   :relations
   [{:relation :zil/formalizes
     :subject-kind :declaration
     :object-kind :claim}
    {:relation :zil/requires
     :subject-kind :declaration
     :object-kind :requirement}
    {:relation :zil/requiresClaim
     :subject-kind :claim
     :object-kind :requirement}
    {:relation :zil/supportedBy
     :subject-kind :declaration
     :object-kind :evidence-source}
    {:relation :zil/supportedBy
     :subject-kind :claim
     :object-kind :evidence-source}]})

(defn- variable-kind
  [variable-kinds term-name]
  (get variable-kinds term-name))

(defn term-kind
  "Resolve a canonical IR term using explicit variable kinds or ground prefixes."
  [variable-kinds term]
  (case (:term/kind term)
    :var (variable-kind variable-kinds (:term/name term))
    :node (infer-ground-kind (:term/name term))
    nil))

(defn validates-relation?
  "Return true when a canonical relation matches a profile signature."
  [profile variable-kinds relation]
  (let [subject-kind (term-kind variable-kinds (:subject relation))
        object-kind (term-kind variable-kinds (:object relation))]
    (boolean
     (and subject-kind
          object-kind
          (some (fn [signature]
                  (and (= (:relation signature) (:relation relation))
                       (= (:subject-kind signature) subject-kind)
                       (= (:object-kind signature) object-kind)))
                (:relations profile))))))

(defn validates-rule?
  "Validate all premises and the single conclusion of canonical Horn-rule IR."
  [profile variable-kinds rule]
  (and (every? #(validates-relation? profile variable-kinds %)
               (:premises rule))
       (validates-relation? profile variable-kinds (:conclusion rule))))
