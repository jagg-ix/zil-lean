(ns zil.plugin.evidence
  "Deterministic ZIL-EVIDENCE/1 envelopes for extension-produced artifacts."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.plugin.manifest :as manifest])
  (:import (java.nio.charset StandardCharsets)
           (java.security MessageDigest)))

(def schema "ZIL-EVIDENCE/1")
(def assurance-levels
  #{"exploratory" "externally-attested" "byte-attested" "validated" "kernel-backed"})

(defn sha256-text [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) StandardCharsets/UTF_8))]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn- valid-sha256? [value]
  (boolean (re-matches #"sha256:[0-9a-f]{64}" (str value))))

(defn- default-assurance [extension-manifest]
  (case (:authority extension-manifest)
    "external" "externally-attested"
    "clojure" "byte-attested"
    "lean" "validated"
    "shared" "byte-attested"
    "exploratory"))

(defn- canonical-metadata [metadata]
  (into (sorted-map)
        (map (fn [[key value]] [(name key) value]))
        (or metadata {})))

(defn make-envelope
  [{:keys [extension role subject input-sha256 payload metadata assurance authority]}]
  (let [extension (manifest/validate! extension)
        authority (or authority (:authority extension))
        assurance (or assurance (default-assurance extension))
        payload (str (or payload ""))
        output-sha256 (sha256-text payload)
        input-sha256 (or input-sha256 (sha256-text ""))]
    (when (str/blank? (str role))
      (throw (ex-info "evidence role must be nonempty" {:kind :evidence-error})))
    (when (str/blank? (str subject))
      (throw (ex-info "evidence subject must be nonempty" {:kind :evidence-error})))
    (when-not (valid-sha256? input-sha256)
      (throw (ex-info "evidence input_sha256 is invalid"
                      {:kind :evidence-error :input-sha256 input-sha256})))
    (when-not (contains? assurance-levels assurance)
      (throw (ex-info "evidence assurance is invalid"
                      {:kind :evidence-error :assurance assurance})))
    (when (and (= "clojure" (:runtime extension))
               (contains? #{"validated" "kernel-backed"} assurance))
      (throw (ex-info "Clojure extensions cannot produce validated or kernel-backed evidence"
                      {:kind :evidence-error :assurance assurance})))
    (let [identity-source
          (str (:id extension) "\n" (:version extension) "\n" role "\n" subject "\n"
               input-sha256 "\n" output-sha256)
          evidence-id (str "evidence:" (subs (sha256-text identity-source) 7))]
      (array-map
       :schema schema
       :evidence_id evidence-id
       :extension_id (:id extension)
       :extension_version (:version extension)
       :authority authority
       :assurance assurance
       :role (str role)
       :subject (str subject)
       :input_sha256 input-sha256
       :output_sha256 output-sha256
       :payload payload
       :metadata (canonical-metadata metadata)))))

(defn canonical-map [envelope]
  (array-map
   "schema" (:schema envelope)
   "evidence_id" (:evidence_id envelope)
   "extension_id" (:extension_id envelope)
   "extension_version" (:extension_version envelope)
   "authority" (:authority envelope)
   "assurance" (:assurance envelope)
   "role" (:role envelope)
   "subject" (:subject envelope)
   "input_sha256" (:input_sha256 envelope)
   "output_sha256" (:output_sha256 envelope)
   "payload" (:payload envelope)
   "metadata" (:metadata envelope)))

(defn canonical-json [envelope]
  (json/write-str (canonical-map envelope)))
