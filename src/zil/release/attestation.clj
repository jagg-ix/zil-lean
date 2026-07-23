(ns zil.release.attestation
  "Create deterministic release attestations from ZIL evidence reports."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str])
  (:import [java.nio.charset StandardCharsets]
           [java.security MessageDigest]))

(def request-format "zil.release-request.v0.1")
(def attestation-format "zil.release-attestation.v0.1")
(def workflow-format "zil.workflow-verification.v0.1")
(def proof-format "zil.proof-token-resolution.v0.1")
(def lock-format "zil.theorem-lock-check.v0.1")
(def accepted-target-statuses #{"verified" "reviewed" "proved"})

(defn- value [m key]
  (if (contains? m key) (get m key) (get m (keyword key))))

(defn- canonical-key [key]
  (if (keyword? key) (name key) (str key)))

(defn- canonical-value [item]
  (cond
    (map? item) (into (sorted-map)
                      (map (fn [[key value]]
                             [(canonical-key key) (canonical-value value)]))
                      item)
    (vector? item) (mapv canonical-value item)
    (sequential? item) (mapv canonical-value item)
    (keyword? item) (name item)
    :else item))

(defn- sha256-bytes [bytes]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256") bytes)]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn text-sha256 [text]
  (sha256-bytes (.getBytes (str text) StandardCharsets/UTF_8)))

(defn file-sha256 [file]
  (sha256-bytes (java.nio.file.Files/readAllBytes (.toPath (io/file file)))))

(defn document-fingerprint [document]
  (text-sha256 (json/write-str (canonical-value document) :escape-slash false)))

(defn- require-value! [condition message data]
  (when-not condition
    (throw (ex-info message (assoc data :code :validation)))))

(defn read-json! [file expected-format]
  (let [path (io/file file)]
    (require-value! (.isFile path) "Evidence file does not exist" {:path (.getPath path)})
    (let [document (json/read-str (slurp path))]
      (require-value! (= expected-format (value document "format"))
                      "Unsupported evidence format"
                      {:path (.getPath path)
                       :expected expected-format
                       :actual (value document "format")})
      document)))

(defn- contained-file! [root raw-path]
  (require-value! (and (string? raw-path) (not (str/blank? raw-path)))
                  "Evidence path must be non-empty" {:path raw-path})
  (let [raw (io/file raw-path)]
    (require-value! (not (.isAbsolute raw))
                    "Release evidence paths must be relative" {:path raw-path})
    (let [root-file (.getCanonicalFile (io/file root))
          target (.getCanonicalFile (io/file root-file raw-path))
          root-path (.toPath root-file)
          target-path (.toPath target)]
      (require-value! (.startsWith target-path root-path)
                      "Release evidence path escapes request directory"
                      {:path raw-path :root (.getPath root-file)})
      target)))

(defn validate-request! [request]
  (require-value! (= request-format (value request "format"))
                  "Unsupported release request format"
                  {:format (value request "format")})
  (doseq [key ["release_id" "module"]]
    (require-value! (and (string? (value request key))
                         (not (str/blank? (value request key))))
                    "Release request field must be non-empty"
                    {:field key}))
  (let [artifacts (value request "artifacts")
        evidence (value request "evidence")]
    (require-value! (and (vector? artifacts) (seq artifacts))
                    "Release request requires at least one artifact" {})
    (let [paths (mapv #(value % "path") artifacts)]
      (require-value! (= (count paths) (count (distinct paths)))
                      "Release artifact paths must be unique" {:paths paths}))
    (doseq [artifact artifacts]
      (require-value! (and (string? (value artifact "path"))
                           (not (str/blank? (value artifact "path"))))
                      "Release artifact path must be non-empty" {:artifact artifact})
      (require-value! (and (string? (value artifact "sha256"))
                           (str/starts-with? (value artifact "sha256") "sha256:"))
                      "Release artifact requires a sha256 fingerprint"
                      {:artifact artifact}))
    (require-value! (map? evidence) "Release request evidence must be an object" {})
    (doseq [key ["workflow" "proof_tokens" "theorem_locks"
                 "authorization" "formalization"]]
      (require-value! (map? (value evidence key))
                      "Release request is missing required evidence"
                      {:evidence key})
      (require-value! (and (string? (value (value evidence key) "path"))
                           (not (str/blank? (value (value evidence key) "path"))))
                      "Release evidence path must be non-empty"
                      {:evidence key})))
  request)

(defn- evidence-row [kind path sha status details]
  (sorted-map
   :kind kind
   :path path
   :sha256 sha
   :status status
   :details details))

(defn- artifact-results [root artifacts]
  (mapv
   (fn [artifact]
     (let [path (value artifact "path")
           expected (value artifact "sha256")
           file (contained-file! root path)]
       (if-not (.isFile file)
         (sorted-map :path path :expected_sha256 expected
                     :actual_sha256 nil :status :missing)
         (let [actual (file-sha256 file)]
           (sorted-map :path path :expected_sha256 expected
                       :actual_sha256 actual
                       :status (if (= expected actual) :verified :hash_mismatch))))))
   artifacts))

(defn- validate-workflow [document module minimum-actions]
  (let [verification (value document "verification")
        status (some-> (value verification "status") name)
        action-count (long (or (value document "action_count") 0))
        failures (cond-> []
                   (not= true (value document "ok"))
                   (conj {:kind :workflow_not_ok})
                   (not= module (value document "module"))
                   (conj {:kind :workflow_module_mismatch
                          :expected module :actual (value document "module")})
                   (not= true (value document "complete"))
                   (conj {:kind :workflow_incomplete})
                   (not= "verified" status)
                   (conj {:kind :workflow_module_not_verified :status status})
                   (< action-count minimum-actions)
                   (conj {:kind :workflow_action_coverage
                          :required minimum-actions :actual action-count})
                   (not (and (string? (value document "output_sha256"))
                             (str/starts-with? (value document "output_sha256") "sha256:")))
                   (conj {:kind :workflow_output_hash_missing}))]
    {:ok (empty? failures)
     :failures failures
     :details {:revision (value document "revision")
               :actions action-count
               :output_sha256 (value document "output_sha256")}}))

(defn- validate-proof [document module]
  (let [token-count (long (or (value document "token_count") 0))
        resolved (long (or (value document "resolved") 0))
        unresolved (long (or (value document "unresolved") 0))
        failures (cond-> []
                   (not= true (value document "ok"))
                   (conj {:kind :proof_tokens_not_ok})
                   (not= module (value document "module"))
                   (conj {:kind :proof_module_mismatch
                          :expected module :actual (value document "module")})
                   (not= token-count resolved)
                   (conj {:kind :proof_resolution_incomplete
                          :tokens token-count :resolved resolved})
                   (not= 0 unresolved)
                   (conj {:kind :proof_tokens_unresolved :count unresolved})
                   (not (string? (value document "event_batch_fingerprint")))
                   (conj {:kind :proof_event_fingerprint_missing})
                   (not (string? (value document "token_batch_fingerprint")))
                   (conj {:kind :proof_token_fingerprint_missing}))]
    {:ok (empty? failures)
     :failures failures
     :details {:tokens token-count
               :event_batch_fingerprint (value document "event_batch_fingerprint")
               :token_batch_fingerprint (value document "token_batch_fingerprint")}}))

(defn- validate-locks [document module proof-document]
  (let [changed (long (or (value document "changed") 0))
        lock-count (long (or (value document "lock_count") 0))
        unchanged (long (or (value document "unchanged") 0))
        same-events (= (value document "current_event_batch_fingerprint")
                       (value proof-document "event_batch_fingerprint"))
        same-tokens (= (value document "current_token_batch_fingerprint")
                       (value proof-document "token_batch_fingerprint"))
        failures (cond-> []
                   (not= true (value document "ok"))
                   (conj {:kind :theorem_locks_not_ok})
                   (not= module (value document "module"))
                   (conj {:kind :theorem_lock_module_mismatch
                          :expected module :actual (value document "module")})
                   (not= 0 changed)
                   (conj {:kind :theorem_statement_drift :changed changed})
                   (not= lock-count unchanged)
                   (conj {:kind :theorem_lock_coverage
                          :locks lock-count :unchanged unchanged})
                   (not same-events)
                   (conj {:kind :theorem_lock_event_snapshot_mismatch})
                   (not same-tokens)
                   (conj {:kind :theorem_lock_token_snapshot_mismatch})
                   (not (string? (value document "lock_document_fingerprint")))
                   (conj {:kind :theorem_lock_fingerprint_missing}))]
    {:ok (empty? failures)
     :failures failures
     :details {:locks lock-count
               :unchanged unchanged
               :lock_document_fingerprint
               (value document "lock_document_fingerprint")}}))

(defn- parse-tab-report! [file expected-header]
  (let [lines (->> (str/split-lines (slurp file))
                   (remove str/blank?)
                   vec)]
    (require-value! (= expected-header (first lines))
                    "Unsupported tab-separated evidence report"
                    {:path (.getPath (io/file file))
                     :expected expected-header
                     :actual (first lines)})
    lines))

(defn- key-value-report [lines]
  (reduce
   (fn [result line]
     (let [parts (str/split line #"\t" -1)]
       (require-value! (= 2 (count parts))
                       "Evidence report row must contain one key and value"
                       {:row line})
       (let [[key result-value] parts]
         (require-value! (not (contains? result key))
                         "Evidence report contains a duplicate key" {:key key})
         (assoc result key result-value))))
   (sorted-map)
   (rest lines)))

(defn- validate-authorization [file config]
  (let [report (key-value-report
                (parse-tab-report! file "ZIL-AUTHORIZATION\t1"))
        expected-object (value config "object")
        expected-relation (value config "relation")
        expected-subject (value config "subject")
        failures (cond-> []
                   (not= "allow" (get report "decision"))
                   (conj {:kind :authorization_denied})
                   (not (contains? #{"direct" "derived"} (get report "source")))
                   (conj {:kind :authorization_source_invalid
                          :source (get report "source")})
                   (not= expected-object (get report "object"))
                   (conj {:kind :authorization_object_mismatch})
                   (not= expected-relation (get report "relation"))
                   (conj {:kind :authorization_relation_mismatch})
                   (not= expected-subject (get report "subject"))
                   (conj {:kind :authorization_subject_mismatch}))]
    {:ok (empty? failures)
     :failures failures
     :details {:object (get report "object")
               :relation (get report "relation")
               :subject (get report "subject")
               :source (get report "source")}}))

(defn- formalization-rows [file]
  (let [lines (parse-tab-report! file "ZIL-FORMALIZATION-PLAN\t1")]
    (mapv
     (fn [line]
       (let [parts (str/split line #"\t" -1)]
         (require-value! (= 10 (count parts))
                         "Formalization plan row has the wrong number of fields"
                         {:row line})
         (let [[kind id status priority readiness dependencies reasons
                module file declaration] parts]
           (require-value! (= "target" kind)
                           "Formalization plan row must begin with target"
                           {:row line})
           {:id id :status status :priority priority :readiness readiness
            :dependencies dependencies :reasons reasons :module module
            :file file :declaration declaration})))
     (rest lines))))

(defn- validate-formalization [file config]
  (let [rows (formalization-rows file)
        by-id (into {} (map (juxt :id identity)) rows)
        required (value config "required_targets")]
    (require-value! (and (vector? required) (seq required)
                         (every? string? required))
                    "Formalization evidence requires target IDs"
                    {:required_targets required})
    (require-value! (= (count rows) (count by-id))
                    "Formalization plan target IDs must be unique" {})
    (let [failures (reduce
                    (fn [out id]
                      (if-let [row (get by-id id)]
                        (if (contains? accepted-target-statuses (:status row))
                          out
                          (conj out {:kind :formalization_target_not_accepted
                                     :target id :status (:status row)}))
                        (conj out {:kind :formalization_target_missing
                                   :target id})))
                    []
                    required)]
      {:ok (empty? failures)
       :failures failures
       :details {:required_targets required
                 :plan_targets (count rows)}})))

(defn- result-with-file [kind path file validation]
  (evidence-row kind path (file-sha256 file)
                (if (:ok validation) :verified :failed)
                (:details validation)))

(defn attest
  [request root]
  (validate-request! request)
  (let [module (value request "module")
        evidence (value request "evidence")
        artifacts (artifact-results root (value request "artifacts"))
        artifact-failures (->> artifacts
                               (remove #(= :verified (:status %)))
                               (mapv #(assoc % :kind :artifact_failure)))
        workflow-config (value evidence "workflow")
        proof-config (value evidence "proof_tokens")
        lock-config (value evidence "theorem_locks")
        authorization-config (value evidence "authorization")
        formalization-config (value evidence "formalization")
        workflow-file (contained-file! root (value workflow-config "path"))
        proof-file (contained-file! root (value proof-config "path"))
        lock-file (contained-file! root (value lock-config "path"))
        authorization-file (contained-file! root (value authorization-config "path"))
        formalization-file (contained-file! root (value formalization-config "path"))
        workflow-document (read-json! workflow-file workflow-format)
        proof-document (read-json! proof-file proof-format)
        lock-document (read-json! lock-file lock-format)
        workflow-result (validate-workflow workflow-document module
                                           (long (or (value workflow-config "minimum_actions") 1)))
        proof-result (validate-proof proof-document module)
        lock-result (validate-locks lock-document module proof-document)
        authorization-result (validate-authorization authorization-file authorization-config)
        formalization-result (validate-formalization formalization-file formalization-config)
        workflow-artifact (value workflow-config "artifact")
        workflow-artifact-row (some #(when (= workflow-artifact (:path %)) %) artifacts)
        workflow-binding-failures
        (cond-> []
          (nil? workflow-artifact-row)
          (conj {:kind :workflow_artifact_missing_from_release
                 :artifact workflow-artifact})
          (and workflow-artifact-row
               (not= (value workflow-document "output_sha256")
                     (:actual_sha256 workflow-artifact-row)))
          (conj {:kind :workflow_artifact_hash_mismatch
                 :artifact workflow-artifact
                 :workflow_sha256 (value workflow-document "output_sha256")
                 :artifact_sha256 (:actual_sha256 workflow-artifact-row)}))
        evidence-results
        [(result-with-file :workflow (value workflow-config "path")
                           workflow-file workflow-result)
         (result-with-file :proof_tokens (value proof-config "path")
                           proof-file proof-result)
         (result-with-file :theorem_locks (value lock-config "path")
                           lock-file lock-result)
         (result-with-file :authorization (value authorization-config "path")
                           authorization-file authorization-result)
         (result-with-file :formalization (value formalization-config "path")
                           formalization-file formalization-result)]
        evidence-failures (vec (concat (:failures workflow-result)
                                       (:failures proof-result)
                                       (:failures lock-result)
                                       (:failures authorization-result)
                                       (:failures formalization-result)
                                       workflow-binding-failures))
        failures (vec (concat artifact-failures evidence-failures))
        body (sorted-map
              :format attestation-format
              :ok (empty? failures)
              :release_id (value request "release_id")
              :module module
              :request_fingerprint (document-fingerprint request)
              :artifacts artifacts
              :evidence evidence-results
              :failures failures)]
    (assoc body :attestation_fingerprint (document-fingerprint body))))

(defn write-json! [path document]
  (when-let [parent (.getParentFile (io/file path))] (.mkdirs parent))
  (spit path (str (json/write-str (canonical-value document)
                                  :escape-slash false) "\n"))
  document)

(defn attest-file! [request-path output-path]
  (let [request-file (.getCanonicalFile (io/file request-path))
        _ (require-value! (.isFile request-file)
                          "Release request file does not exist"
                          {:path request-path})
        root (or (.getParentFile request-file) (.getCanonicalFile (io/file ".")))
        request (json/read-str (slurp request-file))]
    (write-json! output-path (attest request root))))

(def usage
  "zil-release-attest <release-request.json> <attestation.json>")

(defn -main [& args]
  (try
    (if-not (= 2 (count args))
      (do (binding [*out* *err*] (println usage)) (System/exit 2))
      (let [[request output] args
            report (attest-file! request output)]
        (println (json/write-str (canonical-value report) :escape-slash false))
        (System/exit (if (:ok report) 0 1))))
    (catch Exception error
      (binding [*out* *err*] (println (.getMessage error)))
      (System/exit 2))))
