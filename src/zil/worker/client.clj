(ns zil.worker.client
  "Supervise a native Lean JSON Lines worker and add transport SHA-256 attestation."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.worker.protocol :as protocol])
  (:import (java.io BufferedReader BufferedWriter)
           (java.nio.charset StandardCharsets)
           (java.nio.file Files Paths StandardOpenOption)
           (java.security MessageDigest)
           (java.util UUID)
           (java.util.concurrent TimeUnit)))

(def default-command ["lake" "exe" "zilWorker" "--" "--stdio"])

(defn- digest-bytes [^bytes value]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256") value)]
    (str "sha256:"
         (apply str (map #(format "%02x" (bit-and (int %) 0xff)) digest)))))

(defn sha256-text [text]
  (digest-bytes (.getBytes (str text) StandardCharsets/UTF_8)))

(defn sha256-file [path]
  (with-open [input (Files/newInputStream
                     (Paths/get (str path) (make-array String 0))
                     (into-array java.nio.file.OpenOption [StandardOpenOption/READ]))]
    (let [message-digest (MessageDigest/getInstance "SHA-256")
          buffer (byte-array 8192)]
      (loop []
        (let [size (.read input buffer)]
          (when (pos? size)
            (.update message-digest buffer 0 size)
            (recur))))
      (str "sha256:"
           (apply str
                  (map #(format "%02x" (bit-and (int %) 0xff))
                       (.digest message-digest)))))))

(defn request
  "Create a canonical request and bind it to the exact current input bytes."
  [{:keys [request-id operation input-path base-revision arguments capabilities]
    :or {request-id (str "request:" (UUID/randomUUID))
         base-revision "-"
         arguments []}}]
  (let [operation (str operation)
        capability (get protocol/operation-capabilities operation)
        capabilities (or capabilities (when capability [capability]))]
    (protocol/canonical-request
     {:request-id request-id
      :operation operation
      :input-path input-path
      :base-revision base-revision
      :input-sha256 (sha256-file input-path)
      :capabilities capabilities
      :arguments arguments})))

(defrecord Worker
  [^Process process
   ^BufferedWriter writer
   ^BufferedReader reader
   error-lines
   error-drain
   lock])

(defn start-worker!
  ([] (start-worker! {}))
  ([{:keys [command directory environment]
     :or {command default-command environment {}}}]
   (let [builder (ProcessBuilder. ^java.util.List (vec command))
         _ (when directory (.directory builder (io/file directory)))
         process-environment (.environment builder)
         _ (doseq [[key value] environment]
             (.put process-environment (str key) (str value)))
         process (.start builder)
         writer (io/writer (.getOutputStream process))
         reader (io/reader (.getInputStream process))
         errors (atom [])
         error-reader (io/reader (.getErrorStream process))
         error-drain (future
                       (with-open [stream error-reader]
                         (doseq [line (line-seq stream)]
                           (swap! errors conj line))))]
     (->Worker process writer reader errors error-drain (Object.)))))

(defn alive? [^Worker worker]
  (.isAlive ^Process (:process worker)))

(defn- pending-attestation-warning? [value]
  (= "result-sha256-pending-client-attestation" value))

(defn attest-response
  "Add byte attestation without changing Lean authority, assurance, payload, or errors."
  [response]
  (let [payload (or (:payload response) "")]
    (-> response
        (assoc :result_sha256 (sha256-text payload))
        (update :warnings
                (fn [values]
                  (vec (remove pending-attestation-warning? (or values []))))))))

(defn invoke!
  "Send one request to a persistent worker and return the verified, byte-attested response."
  [^Worker worker request]
  (protocol/validate-request! request)
  (locking (:lock worker)
    (when-not (alive? worker)
      (throw (ex-info "Lean worker is not running"
                      {:kind :transport-error
                       :errors @(:error-lines worker)})))
    (.write ^BufferedWriter (:writer worker) (protocol/write-line request))
    (.newLine ^BufferedWriter (:writer worker))
    (.flush ^BufferedWriter (:writer worker))
    (let [line (.readLine ^BufferedReader (:reader worker))]
      (when (nil? line)
        (throw (ex-info "Lean worker closed without a response"
                        {:kind :transport-error
                         :errors @(:error-lines worker)})))
      (->> (protocol/read-line line)
           (protocol/validate-response! request)
           attest-response))))

(defn stop-worker! [^Worker worker]
  (try (.close ^BufferedWriter (:writer worker)) (catch Exception _))
  (when-not (.waitFor ^Process (:process worker) 5 TimeUnit/SECONDS)
    (.destroy ^Process (:process worker))
    (when-not (.waitFor ^Process (:process worker) 2 TimeUnit/SECONDS)
      (.destroyForcibly ^Process (:process worker))))
  (try (.close ^BufferedReader (:reader worker)) (catch Exception _))
  @(:error-drain worker)
  {:exit (.exitValue ^Process (:process worker))
   :errors @(:error-lines worker)})

(defn invoke-once!
  ([request] (invoke-once! {} request))
  ([options request]
   (let [worker (start-worker! options)]
     (try
       (invoke! worker request)
       (finally
         (stop-worker! worker))))))

(defn -main
  [& args]
  (try
    (let [[operation input-path & operation-arguments] args]
      (when (or (str/blank? operation) (str/blank? input-path))
        (throw (ex-info
                "usage: clojure -M:exchange <operation> <input-path> [operation-arguments...]"
                {:kind :invalid-command})))
      (let [response (invoke-once!
                      (request {:operation operation
                                :input-path input-path
                                :arguments operation-arguments}))]
        (println (json/write-str response))
        (System/exit (if (= "ok" (:status response)) 0 1))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
