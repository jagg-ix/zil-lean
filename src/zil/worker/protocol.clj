(ns zil.worker.protocol
  "Language-neutral request construction and response verification for ZIL-EXCHANGE/1."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]))

(def schema "ZIL-EXCHANGE/1")
(def protocol-version 1)

(def operation-capabilities
  {"parse" "parse-v1"
   "expand" "expand-v1"
   "query" "query-v1"
   "authorize" "authorization-v1"
   "impact" "impact-v1"
   "recovery-audit" "recovery-audit-v1"})

(def operation-arities
  {"parse" 0
   "expand" 0
   "query" 1
   "authorize" 3
   "impact" 1
   "recovery-audit" 1})

(def worker-statuses
  #{"ok" "invalid" "unsupported" "error"})

(def pending-attestation-warning
  "result-sha256-pending-client-attestation")

(def request-fields
  ["schema" "request_id" "protocol_version" "operation" "input_path"
   "base_revision" "input_sha256" "capabilities" "arguments"])

(def ^:private request-field-rank
  (zipmap request-fields (range)))

(defn- compare-request-fields [left right]
  (let [left-rank (get request-field-rank left Integer/MAX_VALUE)
        right-rank (get request-field-rank right Integer/MAX_VALUE)]
    (if (= left-rank right-rank)
      (compare left right)
      (compare left-rank right-rank))))

(defn canonical-request
  "Construct a request map with explicit stable field order."
  [{:keys [request-id operation input-path base-revision input-sha256
           capabilities arguments]
    :or {base-revision "-" capabilities [] arguments []}}]
  (into
   (sorted-map-by compare-request-fields)
   [["schema" schema]
    ["request_id" (str request-id)]
    ["protocol_version" protocol-version]
    ["operation" (str operation)]
    ["input_path" (str input-path)]
    ["base_revision" (str base-revision)]
    ["input_sha256" (str input-sha256)]
    ["capabilities" (vec (sort (distinct (map str capabilities))))]
    ["arguments" (vec (map str arguments))]]))

(defn validate-request!
  "Fail closed before a request reaches the Lean worker."
  [request]
  (let [operation (get request "operation")
        capability (get operation-capabilities operation)
        arity (get operation-arities operation)
        capabilities (vec (get request "capabilities" []))
        canonical-capabilities (vec (sort (distinct capabilities)))]
    (when-not (= schema (get request "schema"))
      (throw (ex-info "unsupported exchange schema" {:request request})))
    (when-not (= protocol-version (get request "protocol_version"))
      (throw (ex-info "unsupported protocol version" {:request request})))
    (when (str/blank? (get request "request_id"))
      (throw (ex-info "request_id must be nonempty" {:request request})))
    (when (str/blank? (get request "input_path"))
      (throw (ex-info "input_path must be nonempty" {:request request})))
    (when (str/blank? (get request "base_revision"))
      (throw (ex-info "base_revision must be nonempty" {:request request})))
    (when-not (re-matches #"sha256:[0-9a-fA-F]{64}" (get request "input_sha256" ""))
      (throw (ex-info "input_sha256 must be sha256:<64 hex>" {:request request})))
    (when-not (= canonical-capabilities capabilities)
      (throw (ex-info "capabilities must be sorted and unique" {:request request})))
    (when-not capability
      (throw (ex-info "unsupported operation" {:operation operation})))
    (when-not (some #{capability} capabilities)
      (throw (ex-info "required capability is missing"
                      {:operation operation :capability capability})))
    (when-not (= arity (count (get request "arguments")))
      (throw (ex-info "invalid operation argument count"
                      {:operation operation :expected arity
                       :actual (count (get request "arguments"))})))
    request))

(defn write-line [value]
  (json/write-str value))

(defn read-line [text]
  (json/read-str text :key-fn keyword))

(defn- transport-error [message data]
  (ex-info message (assoc data :kind :transport-error)))

(defn validate-response!
  [request response]
  (when-not (= schema (:schema response))
    (throw (transport-error "worker returned an unsupported schema" {:response response})))
  (when-not (= protocol-version (:protocol_version response))
    (throw (transport-error "worker returned an unsupported protocol version"
                            {:response response})))
  (when-not (= (get request "request_id") (:request_id response))
    (throw (transport-error "worker response request_id mismatch"
                            {:request request :response response})))
  (when-not (= (get request "operation") (:operation response))
    (throw (transport-error "worker response operation mismatch"
                            {:request request :response response})))
  (when-not (= (get request "input_sha256") (:input_sha256 response))
    (throw (transport-error "worker response input_sha256 mismatch"
                            {:request request :response response})))
  (when-not (= "lean" (:authority response))
    (throw (transport-error "worker response lost Lean authority" {:response response})))
  (when-not (contains? worker-statuses (:status response))
    (throw (transport-error "worker returned an unsupported status" {:response response})))
  (when-not (str/blank? (:result_sha256 response))
    (throw (transport-error "Lean worker must leave result_sha256 for client attestation"
                            {:response response})))
  (if (= "ok" (:status response))
    (do
      (when-not (= "validated" (:assurance response))
        (throw (transport-error "successful worker response lost validated assurance"
                                {:response response})))
      (when-not (some #{pending-attestation-warning} (:warnings response))
        (throw (transport-error "successful worker response lost attestation boundary"
                                {:response response}))))
    (do
      (when-not (str/blank? (:assurance response))
        (throw (transport-error "failed worker response must not claim assurance"
                                {:response response})))
      (when (empty? (:errors response))
        (throw (transport-error "failed worker response must include an error"
                                {:response response}))))))
  response)
