(ns zil.bridge.lean-events
  "Validate Lean declaration batches and lower them to ordinary ZIL facts."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str])
  (:import [java.nio.file Files StandardCopyOption]))

(def format-version "zil.lean-events.v0.1")

(defn- require-value! [pred message data]
  (when-not pred (throw (ex-info message (assoc data :code :validation)))))

(defn validate-batch! [batch]
  (require-value! (= format-version (get batch "format"))
                  "Unsupported Lean event format" {:format (get batch "format")})
  (require-value! (true? (get batch "complete"))
                  "Partial Lean declaration batches are quarantined" {})
  (require-value! (= (get batch "event_count") (count (get batch "events")))
                  "Lean event_count does not match events" {})
  (doseq [event (get batch "events")]
    (require-value! (= "linkLeanDecl" (get event "operation"))
                    "Unsupported Lean event operation" {:event event})
    (require-value! (false? (get event "proved_claim"))
                    "Lean metadata must not directly assert that an external claim is proved"
                    {:declaration (get event "declaration")})
    (require-value! (boolean? (get event "kernel_present"))
                    "Lean event lacks kernel presence status" {:event event})
    (require-value! (or (nil? (get event "zil_claim"))
                        (string? (get event "zil_claim")))
                    "Lean event zil_claim must be a string or null" {:event event})
    (require-value! (or (nil? (get event "zil_concept"))
                        (string? (get event "zil_concept")))
                    "Lean event zil_concept must be a string or null" {:event event})
    (require-value! (or (nil? (get event "zil_requires"))
                        (string? (get event "zil_requires")))
                    "Lean event zil_requires must be a string or null" {:event event})
    (require-value! (or (nil? (get event "zil_export"))
                        (boolean? (get event "zil_export")))
                    "Lean event zil_export must be boolean when present" {:event event})
    (doseq [attachment (or (get event "zil_attachments") [])]
      (require-value! (= "elaboration_validated" (get attachment "trust"))
                      "Native ZIL attachment must be elaboration validated"
                      {:attachment attachment})
      (require-value! (and (string? (get attachment "relation"))
                           (not (str/blank? (get attachment "relation"))))
                      "Native ZIL attachment relation must be non-empty"
                      {:attachment attachment})))
  batch)

(defn read-batch [path]
  (-> (slurp path) (json/read-str) validate-batch!))

(defn- q [value] (pr-str (str value)))
(defn- fact [object relation subject]
  (str (q object) "#" relation "@" (q subject) "."))

(defn- attachment-value [value]
  (cond
    (contains? value "symbol") (get value "symbol")
    (contains? value "string") (get value "string")
    (contains? value "integer") (str (get value "integer"))
    (contains? value "boolean") (str "value:" (get value "boolean"))
    :else (throw (ex-info "Unsupported native ZIL attachment value"
                          {:code :validation :value value}))))

(defn event-records [event]
  (let [decl (str "lean:" (get event "declaration"))
        record (fn [relation subject]
                 {"object" decl "relation" relation "subject" subject})
        base [(record "kind" (str "lean_kind:" (get event "kind")))
              (record "defined_in" (str "lean_module:" (get event "module")))
              (record "trust" (str "trust:" (get event "trust")))
              (record "kernel_present" (str "value:" (get event "kernel_present")))
              (record "uses_sorry" (str "value:" (get event "uses_sorry")))
              (record "proved_claim" "value:false")
              (record "export_selected" (str "value:" (true? (get event "zil_export"))))
              (record "type_fingerprint" (get event "type_fingerprint"))]
        dependencies (for [dependency (get event "dependencies")]
                       (record "depends_on" (str "lean:" dependency)))
        claim (get event "zil_claim")
        claim-links (when claim
                      [(record "formalizes" (str "claim:" claim))
                       {"object" (str "claim:" claim)
                        "relation" "formalized_by"
                        "subject" decl}])
        concept (get event "zil_concept")
        concept-links (when concept
                        [(record "mentions" (str "concept:" concept))
                         {"object" (str "concept:" concept)
                          "relation" "mentioned_by"
                          "subject" decl}])
        requirement (get event "zil_requires")
        requirement-links (when requirement
                            [(record "requires" (str "assumption:" requirement))
                             {"object" (str "assumption:" requirement)
                              "relation" "required_by"
                              "subject" decl}])
        attachments (for [attachment (or (get event "zil_attachments") [])]
                      {"object" (attachment-value (get attachment "object"))
                       "relation" (get attachment "relation")
                       "subject" (attachment-value (get attachment "subject"))})]
    (concat base dependencies claim-links concept-links requirement-links attachments)))

(defn- render-record [{:strs [object relation subject]}]
  (fact object relation subject))

(defn render-zil [batch module-name]
  (str "MODULE " module-name ".\n\n"
       "// Generated from a validated, complete Lean declaration batch.\n"
       "// kernel_present is declaration evidence; proved_claim remains false.\n"
       (fact (str "lean_batch:" (get batch "module")) "format" (get batch "format")) "\n"
       (fact (str "lean_batch:" (get batch "module")) "lean_version" (get batch "lean_version")) "\n"
       (fact (str "lean_batch:" (get batch "module")) "complete" "value:true") "\n\n"
       (str/join "\n" (map render-record
                            (mapcat event-records (get batch "events")))) "\n"))

(defn- atomic-spit! [path text]
  (let [target (.toPath (io/file path))
        parent (.getParent target)]
    (when parent (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0)))
    (let [tmp (Files/createTempFile parent ".zil-lean-events-" ".tmp"
                                    (make-array java.nio.file.attribute.FileAttribute 0))]
      (spit (.toFile tmp) text)
      (Files/move tmp target
                  (into-array StandardCopyOption
                              [StandardCopyOption/ATOMIC_MOVE
                               StandardCopyOption/REPLACE_EXISTING])))))

(defn import-events! [input-path output-path module-name]
  (let [batch (read-batch input-path)
        text (render-zil batch module-name)]
    (atomic-spit! output-path text)
    {:ok true
     :input input-path
     :output output-path
     :module module-name
     :complete true
     :event_count (count (get batch "events"))}))
