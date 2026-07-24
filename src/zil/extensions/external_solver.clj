(ns zil.extensions.external-solver
  "Allowlisted external proof-tool adapter producing externally attested evidence."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence]
            [zil.worker.client :as worker-client])
  (:import (java.util.concurrent TimeUnit)))

(def report-schema "ZIL-EXTERNAL-TOOL/1")
(def capabilities ["evidence-producer" "external-solver"])

(defn- command-for [template input-path]
  (mapv #(if (= "{input}" %) (str input-path) (str %)) template))

(defn run-tool!
  [{:keys [tools runner directory environment]
    :or {tools {} environment {}}}
   tool input-path]
  (let [{:keys [command timeout-ms]
         :or {timeout-ms 30000}
         :as descriptor} (get tools (str tool))]
    (when-not descriptor
      (throw (ex-info "external tool is not allowlisted"
                      {:kind :extension-input-error :tool tool})))
    (when-not (and (vector? command) (seq command))
      (throw (ex-info "external tool command must be a nonempty vector"
                      {:kind :extension-configuration-error :tool tool})))
    (let [invocation (command-for command input-path)
          result
          (if runner
            (runner {:tool (str tool)
                     :command invocation
                     :input-path (str input-path)
                     :timeout-ms timeout-ms
                     :directory directory
                     :environment environment})
            (let [builder (ProcessBuilder. ^java.util.List invocation)
                  _ (when directory (.directory builder (io/file directory)))
                  process-environment (.environment builder)
                  _ (doseq [[key value] environment]
                      (.put process-environment (str key) (str value)))
                  process (.start builder)
                  out-future (future (slurp (.getInputStream process)))
                  err-future (future (slurp (.getErrorStream process)))
                  completed (.waitFor process (long timeout-ms) TimeUnit/MILLISECONDS)]
              (when-not completed
                (.destroyForcibly process)
                (.waitFor process)
                (throw (ex-info "external tool timed out"
                                {:kind :external-tool-timeout
                                 :tool tool
                                 :timeout-ms timeout-ms})))
              {:exit (.exitValue process)
               :out @out-future
               :err @err-future
               :command invocation}))]
      (array-map
       :schema report-schema
       :tool (str tool)
       :command (vec (:command result invocation))
       :input (str input-path)
       :input-sha256 (worker-client/sha256-file input-path)
       :exit (:exit result)
       :stdout (str (or (:out result) ""))
       :stdout-sha256 (evidence/sha256-text (or (:out result) ""))
       :stderr (str (or (:err result) ""))
       :stderr-sha256 (evidence/sha256-text (or (:err result) ""))
       :ok (zero? (long (:exit result)))))))

(defrecord ExternalSolver [extension-manifest config]
  api/Extension
  (extension-manifest [_] extension-manifest)
  (start-extension! [this _] this)
  (stop-extension! [_ _] nil)

  api/Capability
  (provided-capabilities [_] capabilities)

  api/CommandProvider
  (provided-commands [_]
    {"solver-run"
     {:summary "Run one configured external proof tool without a shell"
      :arguments ["tool" "input-path"]
      :authority :external}})
  (invoke-extension-command! [_ command _ arguments]
    (when-not (= "solver-run" command)
      (throw (ex-info "unsupported external solver command"
                      {:kind :unknown-extension-command :command command})))
    (when-not (= 2 (count arguments))
      (throw (ex-info "solver-run requires tool and input-path arguments"
                      {:kind :extension-input-error :arguments arguments})))
    (run-tool! config (first arguments) (second arguments)))

  api/EvidenceProducer
  (produce-evidence! [_ context request]
    (let [tool (:tool request)
          input-path (:input-path request)
          report (run-tool! config tool input-path)
          extension (or (:extension-manifest context) extension-manifest)]
      (evidence/make-envelope
       {:extension extension
        :authority "external"
        :assurance "externally-attested"
        :role (or (:role request) "external-proof-tool")
        :subject (or (:subject request) (str "artifact:" input-path))
        :input-sha256 (:input-sha256 report)
        :payload (json/write-str report)
        :metadata {:tool (:tool report)
                   :exit (:exit report)
                   :ok (:ok report)}}))))

(defn create [extension-manifest config]
  (->ExternalSolver extension-manifest config))
