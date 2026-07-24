(ns zil.plugin.manifest
  "Validation and deterministic fingerprinting for ZIL-EXTENSION/1 manifests."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str])
  (:import (java.nio.charset StandardCharsets)
           (java.security MessageDigest)))

(def schema "ZIL-EXTENSION/1")
(def runtimes #{"lean" "clojure" "external"})
(def authorities #{"lean" "clojure" "shared" "external"})
(def semantic-version-pattern
  #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")

(def canonical-fields
  [:schema :id :version :runtime :entrypoint :capabilities :requires
   :inputs :outputs :authority :trusted])

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) StandardCharsets/UTF_8))]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn- sorted-unique [values]
  (vec (sort (distinct (map str (or values []))))))

(defn normalize
  [manifest]
  (let [manifest (if (every? keyword? (keys manifest))
                   manifest
                   (into {} (map (fn [[key value]] [(keyword key) value]) manifest))]
    (array-map
     :schema (str (:schema manifest))
     :id (str (:id manifest))
     :version (str (:version manifest))
     :runtime (str (:runtime manifest))
     :entrypoint (str (:entrypoint manifest))
     :capabilities (sorted-unique (:capabilities manifest))
     :requires (sorted-unique (:requires manifest))
     :inputs (sorted-unique (:inputs manifest))
     :outputs (sorted-unique (:outputs manifest))
     :authority (str (:authority manifest))
     :trusted (boolean (:trusted manifest)))))

(defn validate!
  [manifest]
  (let [manifest (normalize manifest)]
    (when-not (= schema (:schema manifest))
      (throw (ex-info "unsupported extension manifest schema"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when (or (str/blank? (:id manifest))
              (not (str/starts-with? (:id manifest) "extension:")))
      (throw (ex-info "extension id must begin with extension:"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when-not (re-matches semantic-version-pattern (:version manifest))
      (throw (ex-info "extension version must be semantic"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when-not (contains? runtimes (:runtime manifest))
      (throw (ex-info "extension runtime is invalid"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when (str/blank? (:entrypoint manifest))
      (throw (ex-info "extension entrypoint must be nonempty"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when-not (contains? authorities (:authority manifest))
      (throw (ex-info "extension authority is invalid"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when (and (= "clojure" (:runtime manifest))
               (contains? #{"lean" "shared"} (:authority manifest)))
      (throw (ex-info "Clojure extensions cannot claim Lean or shared authority"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when (and (= "external" (:runtime manifest))
               (not= "external" (:authority manifest)))
      (throw (ex-info "external extensions must declare external authority"
                      {:kind :extension-manifest-error :manifest manifest})))
    (when (and (:trusted manifest)
               (not= "lean" (:runtime manifest)))
      (throw (ex-info "trusted=true is reserved for configured Lean extensions"
                      {:kind :extension-manifest-error :manifest manifest})))
    manifest))

(defn canonical-map [manifest]
  (let [manifest (validate! manifest)]
    (into (array-map)
          (map (fn [field] [(name field) (get manifest field)]))
          canonical-fields)))

(defn canonical-json [manifest]
  (json/write-str (canonical-map manifest)))

(defn fingerprint [manifest]
  (sha256 (canonical-json manifest)))

(defn read-manifest [path]
  (with-open [reader (io/reader path)]
    (validate! (json/read reader :key-fn keyword))))

(defn with-fingerprint [manifest]
  (let [manifest (validate! manifest)]
    (assoc manifest :fingerprint (fingerprint manifest))))
