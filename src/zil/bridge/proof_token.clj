(ns zil.bridge.proof-token
  "Resolve proof tokens against complete Lean declaration event batches."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.bridge.lean-events :as lean-events])
  (:import [java.nio.charset StandardCharsets]
           [java.security MessageDigest]))

(def token-format "zil.proof-tokens.v0.1")
(def resolution-format "zil.proof-token-resolution.v0.1")
(def default-trust #{"kernel_checked_term"})

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) StandardCharsets/UTF_8))]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn- require-value! [condition message data]
  (when-not condition
    (throw (ex-info message (assoc data :code :validation)))))

(defn- canonical-value [value]
  (cond
    (map? value) (into (sorted-map)
                       (map (fn [[key item]] [(str key) (canonical-value item)]))
                       value)
    (vector? value) (mapv canonical-value value)
    (sequential? value) (mapv canonical-value value)
    :else value))

(defn batch-fingerprint [batch]
  (sha256 (json/write-str (canonical-value batch) :escape-slash false)))

(defn validate-token-batch! [batch]
  (require-value! (= token-format (get batch "format"))
                  "Unsupported proof token format"
                  {:format (get batch "format")})
  (require-value! (true? (get batch "complete"))
                  "Partial proof token batches are rejected" {})
  (require-value! (and (string? (get batch "module"))
                       (not (str/blank? (get batch "module"))))
                  "Proof token batch module must be non-empty" {})
  (let [tokens (get batch "tokens")]
    (require-value! (vector? tokens)
                    "Proof token batch tokens must be an array" {})
    (require-value! (= (get batch "token_count") (count tokens))
                    "Proof token_count does not match tokens" {})
    (let [ids (mapv #(get % "token_id") tokens)]
      (require-value! (= (count ids) (count (distinct ids)))
                      "Proof token IDs must be unique" {:token_ids ids}))
    (doseq [token tokens]
      (require-value! (and (string? (get token "token_id"))
                           (not (str/blank? (get token "token_id"))))
                      "Proof token ID must be non-empty" {:token token})
      (require-value! (and (string? (get token "declaration"))
                           (not (str/blank? (get token "declaration"))))
                      "Proof token declaration must be non-empty" {:token token})
      (require-value! (or (nil? (get token "expected_kind"))
                          (and (string? (get token "expected_kind"))
                               (not (str/blank? (get token "expected_kind")))))
                      "Proof token expected_kind must be a non-empty string"
                      {:token token})
      (require-value! (or (nil? (get token "acceptable_trust"))
                          (and (vector? (get token "acceptable_trust"))
                               (every? string? (get token "acceptable_trust"))
                               (seq (get token "acceptable_trust"))))
                      "Proof token acceptable_trust must be a non-empty string array"
                      {:token token})
      (require-value! (or (nil? (get token "claim"))
                          (string? (get token "claim")))
                      "Proof token claim must be a string or null" {:token token})))
  batch)

(defn read-token-batch [path]
  (-> (slurp path) json/read-str validate-token-batch!))

(defn read-event-batch [path]
  (lean-events/read-batch path))

(defn- event-index [events]
  (group-by #(get % "declaration") events))

(defn- token-trust [token]
  (set (or (get token "acceptable_trust") default-trust)))

(defn- base-resolution [token]
  (cond-> (sorted-map
           :token_id (get token "token_id")
           :declaration (get token "declaration"))
    (get token "expected_kind")
    (assoc :expected_kind (get token "expected_kind"))
    (get token "claim")
    (assoc :claim (get token "claim")
           :claim_status :external_unproved)))

(defn resolve-token [module index token]
  (let [matches (vec (get index (get token "declaration") []))
        base (base-resolution token)]
    (cond
      (empty? matches)
      (assoc base :status :missing)

      (> (count matches) 1)
      (assoc base :status :ambiguous :match_count (count matches))

      :else
      (let [event (first matches)
            event-module (get event "module")
            expected-kind (get token "expected_kind")
            acceptable-trust (token-trust token)
            actual-trust (get event "trust")]
        (cond
          (not= module event-module)
          (assoc base :status :module_mismatch
                 :expected_module module
                 :actual_module event-module)

          (and expected-kind (not= expected-kind (get event "kind")))
          (assoc base :status :kind_mismatch
                 :actual_kind (get event "kind"))

          (not (true? (get event "kernel_present")))
          (assoc base :status :kernel_missing)

          (true? (get event "uses_sorry"))
          (assoc base :status :uses_sorry)

          (not (contains? acceptable-trust actual-trust))
          (assoc base :status :trust_mismatch
                 :actual_trust actual-trust
                 :acceptable_trust (vec (sort acceptable-trust)))

          :else
          (assoc base
                 :status :resolved
                 :module event-module
                 :kind (get event "kind")
                 :trust actual-trust
                 :kernel_present true
                 :uses_sorry false
                 :type_fingerprint (get event "type_fingerprint")
                 :dependencies (vec (sort (or (get event "dependencies") [])))))))))

(defn resolve-batches [token-batch event-batch]
  (validate-token-batch! token-batch)
  (lean-events/validate-batch! event-batch)
  (let [module (get token-batch "module")
        event-module (get event-batch "module")]
    (require-value! (= module event-module)
                    "Proof token and Lean event batches target different modules"
                    {:token_module module :event_module event-module})
    (let [index (event-index (get event-batch "events"))
          resolutions (mapv #(resolve-token module index %)
                            (get token-batch "tokens"))
          counts (frequencies (map :status resolutions))
          ok (every? #(= :resolved (:status %)) resolutions)]
      (sorted-map
       :format resolution-format
       :ok ok
       :module module
       :lean_version (get event-batch "lean_version")
       :event_batch_fingerprint (batch-fingerprint event-batch)
       :token_batch_fingerprint (batch-fingerprint token-batch)
       :token_count (count resolutions)
       :resolved (get counts :resolved 0)
       :unresolved (- (count resolutions) (get counts :resolved 0))
       :status_counts (into (sorted-map) counts)
       :resolutions resolutions))))

(defn write-resolution! [token-path event-path output-path]
  (let [report (resolve-batches (read-token-batch token-path)
                                (read-event-batch event-path))]
    (when-let [parent (.getParentFile (io/file output-path))]
      (.mkdirs parent))
    (spit output-path
          (str (json/write-str (canonical-value report) :escape-slash false)
               "\n"))
    report))

(def usage
  "zil-proof-tokens <tokens.json> <lean-events.json> <resolution.json>")

(defn -main [& args]
  (try
    (if-not (= 3 (count args))
      (do
        (binding [*out* *err*] (println usage))
        (System/exit 2))
      (let [[token-path event-path output-path] args
            report (write-resolution! token-path event-path output-path)]
        (println (json/write-str (canonical-value report) :escape-slash false))
        (System/exit (if (:ok report) 0 1))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error)))
      (System/exit 2))))
