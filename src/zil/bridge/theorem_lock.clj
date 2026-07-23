(ns zil.bridge.theorem-lock
  "Create and check theorem statement locks from resolved proof tokens."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.bridge.proof-token :as proof-token])
  (:import [java.nio.charset StandardCharsets]
           [java.security MessageDigest]))

(def lock-format "zil.theorem-locks.v0.1")
(def check-format "zil.theorem-lock-check.v0.1")
(def resolution-statuses
  #{"resolved" "missing" "ambiguous" "module_mismatch" "kind_mismatch"
    "kernel_missing" "uses_sorry" "trust_mismatch"})

(defn- value [m key]
  (if (contains? m key)
    (get m key)
    (get m (keyword key))))

(defn- without-key [m key]
  (dissoc m key (keyword key)))

(defn- require-value! [condition message data]
  (when-not condition
    (throw (ex-info message (assoc data :code :validation)))))

(defn- canonical-value [item]
  (cond
    (map? item) (into (sorted-map)
                      (map (fn [[key value]] [(name key) (canonical-value value)]))
                      item)
    (vector? item) (mapv canonical-value item)
    (sequential? item) (mapv canonical-value item)
    (keyword? item) (name item)
    :else item))

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes (str text) StandardCharsets/UTF_8))]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn document-fingerprint [document]
  (sha256 (json/write-str (canonical-value document) :escape-slash false)))

(defn- status-name [row]
  (some-> (value row "status") name))

(defn validate-resolution! [resolution]
  (require-value! (= proof-token/resolution-format (value resolution "format"))
                  "Unsupported proof token resolution format"
                  {:format (value resolution "format")})
  (require-value! (and (string? (value resolution "module"))
                       (not (str/blank? (value resolution "module"))))
                  "Proof token resolution module must be non-empty" {})
  (let [rows (value resolution "resolutions")]
    (require-value! (vector? rows)
                    "Proof token resolutions must be an array" {})
    (require-value! (= (value resolution "token_count") (count rows))
                    "Proof token resolution count mismatch" {})
    (let [ids (mapv #(value % "token_id") rows)]
      (require-value! (= (count ids) (count (distinct ids)))
                      "Resolved proof token IDs must be unique"
                      {:token_ids ids}))
    (doseq [row rows]
      (doseq [key ["token_id" "declaration"]]
        (require-value! (and (string? (value row key))
                             (not (str/blank? (value row key))))
                        "Proof token resolution field must be non-empty"
                        {:field key :resolution row}))
      (require-value! (contains? resolution-statuses (status-name row))
                      "Unknown proof token resolution status"
                      {:status (value row "status") :resolution row})
      (when (= "resolved" (status-name row))
        (doseq [key ["module" "kind" "type_fingerprint"]]
          (require-value! (and (string? (value row key))
                               (not (str/blank? (value row key))))
                          "Resolved proof token field must be non-empty"
                          {:field key :resolution row})))))
  resolution)

(defn- resolved? [row]
  (= "resolved" (status-name row)))

(defn- resolution-lock [row]
  (sorted-map
   :token_id (value row "token_id")
   :declaration (value row "declaration")
   :module (value row "module")
   :kind (value row "kind")
   :type_fingerprint (value row "type_fingerprint")))

(defn create-locks
  ([resolution]
   (create-locks resolution {:strict true}))
  ([resolution {:keys [strict] :or {strict true}}]
   (validate-resolution! resolution)
   (let [rows (value resolution "resolutions")
         unresolved (filterv (complement resolved?) rows)]
     (require-value! (empty? unresolved)
                     "Theorem locks require a fully resolved proof token report"
                     {:unresolved (mapv #(select-keys % ["token_id" "status"
                                                         :token_id :status])
                                       unresolved)})
     (let [locks (->> rows (map resolution-lock) (sort-by :token_id) vec)
           declarations (mapv :declaration locks)]
       (require-value! (= (count declarations) (count (distinct declarations)))
                       "Theorem lock declarations must be unique"
                       {:declarations declarations})
       (let [body (sorted-map
                   :format lock-format
                   :complete true
                   :module (value resolution "module")
                   :strict (boolean strict)
                   :source_event_batch_fingerprint
                   (value resolution "event_batch_fingerprint")
                   :source_token_batch_fingerprint
                   (value resolution "token_batch_fingerprint")
                   :lock_count (count locks)
                   :locks locks)]
         (assoc body :document_fingerprint (document-fingerprint body)))))))

(defn validate-locks! [locks]
  (require-value! (= lock-format (value locks "format"))
                  "Unsupported theorem lock format"
                  {:format (value locks "format")})
  (require-value! (true? (value locks "complete"))
                  "Partial theorem lock files are rejected" {})
  (let [module (value locks "module")]
    (require-value! (and (string? module) (not (str/blank? module)))
                    "Theorem lock module must be non-empty" {})
    (require-value! (boolean? (value locks "strict"))
                    "Theorem lock strict flag must be boolean" {})
    (let [rows (value locks "locks")]
      (require-value! (vector? rows) "Theorem locks must be an array" {})
      (require-value! (= (value locks "lock_count") (count rows))
                      "Theorem lock count mismatch" {})
      (let [ids (mapv #(value % "token_id") rows)
            declarations (mapv #(value % "declaration") rows)]
        (require-value! (= (count ids) (count (distinct ids)))
                        "Theorem lock token IDs must be unique" {:token_ids ids})
        (require-value! (= (count declarations) (count (distinct declarations)))
                        "Theorem lock declarations must be unique"
                        {:declarations declarations}))
      (doseq [row rows]
        (doseq [key ["token_id" "declaration" "module" "kind"
                     "type_fingerprint"]]
          (require-value! (and (string? (value row key))
                               (not (str/blank? (value row key))))
                          "Theorem lock field must be a non-empty string"
                          {:field key :lock row}))
        (require-value! (= module (value row "module"))
                        "Theorem lock row module differs from document module"
                        {:document_module module :lock row})))
    (let [fingerprint (value locks "document_fingerprint")]
      (require-value! (and (string? fingerprint)
                           (not (str/blank? fingerprint)))
                      "Theorem lock document fingerprint must be non-empty" {})
      (require-value! (= fingerprint
                         (document-fingerprint
                          (without-key locks "document_fingerprint")))
                      "Theorem lock document fingerprint mismatch"
                      {:expected (document-fingerprint
                                  (without-key locks "document_fingerprint"))
                       :actual fingerprint})))
  locks)

(defn- compare-lock [lock current]
  (let [base (sorted-map
              :token_id (value lock "token_id")
              :declaration (value lock "declaration"))]
    (cond
      (nil? current)
      (assoc base :status :missing_token)

      (not (resolved? current))
      (assoc base :status :current_unresolved
             :current_status (keyword (status-name current)))

      (not= (value lock "declaration") (value current "declaration"))
      (assoc base :status :declaration_changed
             :current_declaration (value current "declaration"))

      (not= (value lock "module") (value current "module"))
      (assoc base :status :module_changed
             :locked_module (value lock "module")
             :current_module (value current "module"))

      (not= (value lock "kind") (value current "kind"))
      (assoc base :status :kind_changed
             :locked_kind (value lock "kind")
             :current_kind (value current "kind"))

      (not= (value lock "type_fingerprint")
            (value current "type_fingerprint"))
      (assoc base :status :fingerprint_changed
             :locked_type_fingerprint (value lock "type_fingerprint")
             :current_type_fingerprint (value current "type_fingerprint"))

      :else
      (assoc base
             :status :unchanged
             :type_fingerprint (value lock "type_fingerprint")))))

(defn check-locks [locks resolution]
  (validate-locks! locks)
  (validate-resolution! resolution)
  (let [lock-module (value locks "module")
        current-module (value resolution "module")
        current-rows (value resolution "resolutions")
        current-index (into {} (map (juxt #(value % "token_id") identity))
                            current-rows)
        locked-rows (value locks "locks")
        locked-ids (set (map #(value % "token_id") locked-rows))
        comparisons (mapv #(compare-lock %
                                         (get current-index (value % "token_id")))
                          locked-rows)
        extra-ids (->> current-rows
                       (map #(value % "token_id"))
                       (remove locked-ids)
                       sort
                       vec)
        extra-status (if (value locks "strict")
                       :unexpected_token
                       :additional_allowed)
        extras (mapv #(sorted-map :token_id % :status extra-status) extra-ids)
        module-failure (when (not= lock-module current-module)
                         {:kind :resolution_module_changed
                          :locked_module lock-module
                          :current_module current-module})
        all-results (vec (concat comparisons extras))
        row-failures (filterv #(not (contains? #{:unchanged :additional_allowed}
                                               (:status %)))
                              all-results)
        counts (frequencies (map :status all-results))
        ok (and (nil? module-failure) (empty? row-failures))]
    (sorted-map
     :format check-format
     :ok ok
     :module lock-module
     :strict (value locks "strict")
     :lock_document_fingerprint (value locks "document_fingerprint")
     :current_event_batch_fingerprint
     (value resolution "event_batch_fingerprint")
     :current_token_batch_fingerprint
     (value resolution "token_batch_fingerprint")
     :lock_count (count locked-rows)
     :current_token_count (count current-rows)
     :unchanged (get counts :unchanged 0)
     :changed (+ (count row-failures) (if module-failure 1 0))
     :status_counts (into (sorted-map) counts)
     :failures (cond-> [] module-failure (conj module-failure))
     :results all-results)))

(defn read-json [path]
  (json/read-str (slurp path)))

(defn write-json! [path document]
  (when-let [parent (.getParentFile (io/file path))]
    (.mkdirs parent))
  (spit path
        (str (json/write-str (canonical-value document) :escape-slash false)
             "\n"))
  document)

(defn create-lock-file! [resolution-path output-path]
  (write-json! output-path (create-locks (read-json resolution-path))))

(defn check-lock-file! [lock-path resolution-path output-path]
  (write-json! output-path
               (check-locks (read-json lock-path)
                            (read-json resolution-path))))

(def usage
  (str "zil-theorem-locks create <resolution.json> <locks.json>\n"
       "zil-theorem-locks check <locks.json> <resolution.json> <report.json>"))

(defn -main [& args]
  (try
    (case (first args)
      "create"
      (if (= 3 (count args))
        (let [[_ resolution-path output-path] args
              locks (create-lock-file! resolution-path output-path)]
          (println (json/write-str (canonical-value locks) :escape-slash false))
          (System/exit 0))
        (do (binding [*out* *err*] (println usage)) (System/exit 2)))

      "check"
      (if (= 4 (count args))
        (let [[_ lock-path resolution-path output-path] args
              report (check-lock-file! lock-path resolution-path output-path)]
          (println (json/write-str (canonical-value report) :escape-slash false))
          (System/exit (if (:ok report) 0 1)))
        (do (binding [*out* *err*] (println usage)) (System/exit 2)))

      (do (binding [*out* *err*] (println usage)) (System/exit 2)))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
