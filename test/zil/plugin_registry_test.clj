(ns zil.plugin-registry-test
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.test :refer [deftest is]]
            [zil.control.capability :as capability]
            [zil.control.runtime :as runtime]
            [zil.extensions.external-solver :as external-solver]
            [zil.extensions.report-exporter :as report-exporter]
            [zil.extensions.repository-scanner :as repository-scanner]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence]
            [zil.plugin.manifest :as manifest]
            [zil.plugin.registry :as registry])
  (:import (java.nio.file Files)
           (java.nio.file.attribute FileAttribute)))

(defn- temp-dir []
  (.toFile (Files/createTempDirectory "zil-extension-test-"
                                      (make-array FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(defn- control-plane
  ([] (control-plane nil))
  ([pool]
   (runtime/->ControlPlane pool (capability/load-valid-inventory) (atom false) {})))

(defrecord TestExtension [manifest-value runtime-capabilities commands invoke-fn]
  api/Extension
  (extension-manifest [_] manifest-value)
  (start-extension! [this _] this)
  (stop-extension! [_ _] nil)

  api/Capability
  (provided-capabilities [_] runtime-capabilities)

  api/CommandProvider
  (provided-commands [_] commands)
  (invoke-extension-command! [_ command _ arguments]
    (invoke-fn command arguments)))

(defn- test-manifest [id capabilities]
  {:schema manifest/schema
   :id id
   :version "1.0.0"
   :runtime "clojure"
   :entrypoint "zil.plugin-registry-test/create"
   :capabilities capabilities
   :requires ["ZIL-EXTENSION/1"]
   :inputs []
   :outputs []
   :authority "clojure"
   :trusted false})

(deftest manifest-fingerprint-is-independent-of-array-order
  (let [left (test-manifest "extension:fingerprint" ["beta" "alpha" "alpha"])
        right (test-manifest "extension:fingerprint" ["alpha" "beta"])]
    (is (= ["alpha" "beta"] (:capabilities (manifest/validate! left))))
    (is (= (manifest/fingerprint left) (manifest/fingerprint right)))
    (is (.startsWith (manifest/canonical-json left)
                     "{\"schema\":\"ZIL-EXTENSION/1\",\"id\":"))))

(deftest registry-forbids-all-declared-built-in-command-shadowing
  (let [extension
        (->TestExtension
         (test-manifest "extension:shadow" ["shadow-test"])
         ["shadow-test"]
         {"action-token" {:authority :clojure}}
         (fn [_ _] :never))
        extension-registry (registry/create-registry {:control-plane (control-plane)})]
    (try
      (is (thrown-with-msg? clojure.lang.ExceptionInfo
                            #"shadows a built-in command"
                            (registry/register! extension-registry extension)))
      (finally
        (registry/close! extension-registry)))))

(deftest worker-requirements-need-a-live-control-plane-profile
  (let [extension
        (->TestExtension
         (assoc (test-manifest "extension:worker-dependent" ["worker-dependent"])
                :requires ["compile-v1"])
         ["worker-dependent"]
         {}
         (fn [_ _] :unused))
        offline (registry/create-registry {:control-plane (control-plane)})
        online (registry/create-registry {:control-plane (control-plane :fake-worker-pool)})]
    (try
      (is (thrown-with-msg? clojure.lang.ExceptionInfo
                            #"requirements are unavailable"
                            (registry/register! offline extension)))
      (is (= "extension:worker-dependent"
             (:id (registry/register! online extension))))
      (finally
        (registry/close! offline)
        (registry/close! online)))))

(deftest invocation-failure-quarantines-extension
  (let [extension
        (->TestExtension
         (test-manifest "extension:failure" ["failure-test"])
         ["failure-test"]
         {"failure-command" {:authority :clojure}}
         (fn [_ _] (throw (ex-info "boom" {:detail :test}))))
        extension-registry (registry/create-registry {:control-plane (control-plane)})]
    (try
      (registry/register! extension-registry extension)
      (is (thrown-with-msg? clojure.lang.ExceptionInfo
                            #"extension invocation failed"
                            (registry/invoke-command! extension-registry
                                                      "failure-command" {} [])))
      (is (= :quarantined
             (registry/extension-status extension-registry "extension:failure")))
      (finally
        (registry/close! extension-registry)))))

(deftest repository-scanner-command-and-evidence-are-deterministic
  (let [root (temp-dir)
        _ (write! root "b.txt" "beta\n")
        _ (write! root "a.txt" "alpha\n")
        extension-manifest
        (manifest/read-manifest
         "extensions/reference/repository-scanner/extension.json")
        extension (repository-scanner/create extension-manifest {})
        extension-registry (registry/create-registry {:control-plane (control-plane)})]
    (try
      (registry/register! extension-registry extension)
      (let [result (registry/invoke-command! extension-registry
                                             "repository-scan" {}
                                             [(.getPath root)])
            report (:result result)
            envelopes (registry/produce-evidence!
                       extension-registry "extension:repository-scanner" {}
                       {:root (.getPath root)
                        :subject "repository:test"})]
        (is (= ["a.txt" "b.txt"] (mapv :path (:entries report))))
        (is (= 2 (:file-count report)))
        (is (= 1 (count envelopes)))
        (is (= evidence/schema (:schema (first envelopes))))
        (is (= "byte-attested" (:assurance (first envelopes))))
        (is (= (:output_sha256 (first envelopes))
               (evidence/sha256-text (:payload (first envelopes))))))
      (finally
        (registry/close! extension-registry)))))

(deftest external-solver-is-allowlisted-and-externally-attested
  (let [root (temp-dir)
        input (write! root "goal.smt2" "(check-sat)\n")
        extension-manifest
        (manifest/read-manifest "extensions/reference/external-solver/extension.json")
        config {:tools {"z3" {:command ["z3" "{input}"] :timeout-ms 100}}
                :runner (fn [{:keys [command]}]
                          {:exit 0 :out "sat\n" :err "" :command command})}
        extension (external-solver/create extension-manifest config)
        extension-registry (registry/create-registry {:control-plane (control-plane)})]
    (try
      (registry/register! extension-registry extension)
      (let [result (:result (registry/invoke-command!
                             extension-registry "solver-run" {}
                             ["z3" (.getPath input)]))
            envelope (first (registry/produce-evidence!
                             extension-registry "extension:external-solver" {}
                             {:tool "z3"
                              :input-path (.getPath input)
                              :subject "obligation:test"}))]
        (is (:ok result))
        (is (= "sat\n" (:stdout result)))
        (is (= "external" (:authority envelope)))
        (is (= "externally-attested" (:assurance envelope))))
      (finally
        (registry/close! extension-registry)))))

(deftest report-exporter-produces-canonical-output
  (let [root (temp-dir)
        input (write! root "report.edn" "{:z 2 :a #{3 1 2}}\n")
        output (io/file root "report.json")
        report (report-exporter/export-report! (.getPath input)
                                                (.getPath output)
                                                "json")
        decoded (json/read-str (slurp output) :key-fn keyword)]
    (is (= "ZIL-REPORT-EXPORT/1" (:schema report)))
    (is (= [1 2 3] (:a decoded)))
    (is (re-matches #"sha256:[0-9a-f]{64}" (:output-sha256 report)))))
