(ns zil.release-attestation-test
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.workflow-runner :as workflow-runner]
            [zil.release.attestation :as attestation]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-release-attestation-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(defn- write-json! [root relative document]
  (write! root relative
          (str (json/write-str document :escape-slash false) "\n")))

(defn- evidence-fixture []
  (let [root (temp-dir)
        artifact (write! root "workflow/Demo.lean"
                         "import Zil.Workflow\nnamespace Demo\nend Demo\n")
        artifact-sha (attestation/file-sha256 artifact)
        workflow
        {"format" attestation/workflow-format
         "ok" true
         "module" "Demo"
         "revision" "rev:1"
         "complete" true
         "action_count" 1
         "output" "workflow/Demo.lean"
         "output_sha256" artifact-sha
         "verification" {"status" "verified"}}
        proof-row
        {"token_id" "proof:demo"
         "declaration" "Demo.answer"
         "status" "resolved"
         "module" "Demo"
         "kind" "theorem"
         "type_fingerprint" "lean-hash:demo-v1"}
        proof
        {"format" attestation/proof-format
         "ok" true
         "module" "Demo"
         "token_count" 1
         "resolved" 1
         "unresolved" 0
         "event_batch_fingerprint" "sha256:events"
         "token_batch_fingerprint" "sha256:tokens"
         "resolutions" [proof-row]}
        lock-row
        {"token_id" "proof:demo"
         "declaration" "Demo.answer"
         "status" "unchanged"
         "type_fingerprint" "lean-hash:demo-v1"}
        locks
        {"format" attestation/lock-format
         "ok" true
         "module" "Demo"
         "lock_count" 1
         "unchanged" 1
         "changed" 0
         "lock_document_fingerprint" "sha256:locks"
         "current_event_batch_fingerprint" "sha256:events"
         "current_token_batch_fingerprint" "sha256:tokens"
         "results" [lock-row]}
        authorization
        (str "ZIL-AUTHORIZATION\t1\n"
             "decision\tallow\n"
             "source\tderived\n"
             "object\trepo.release\n"
             "relation\tzil.publisher\n"
             "subject\tagent.release\n"
             "base-facts\t4\n"
             "closed-facts\t7\n"
             "deriving-rules\tzil.releasePublisher\n")
        formalization
        (str "ZIL-FORMALIZATION-PLAN\t1\n"
             "target\tfoundations\tverified\t100\tblocked\t\tstatus:verified\tDemo\tFoundation.lean\tDemo.foundation\n")
        _ (write-json! root "evidence/workflow.json" workflow)
        _ (write-json! root "evidence/proof.json" proof)
        _ (write-json! root "evidence/locks.json" locks)
        _ (write! root "evidence/authorization.txt" authorization)
        _ (write! root "evidence/formalization.txt" formalization)
        request
        {"format" attestation/request-format
         "release_id" "release:demo-v1"
         "module" "Demo"
         "artifacts" [{"path" "workflow/Demo.lean"
                        "sha256" artifact-sha}]
         "evidence"
         {"workflow" {"path" "evidence/workflow.json"
                      "artifact" "workflow/Demo.lean"
                      "minimum_actions" 1}
          "proof_tokens" {"path" "evidence/proof.json"}
          "theorem_locks" {"path" "evidence/locks.json"}
          "authorization" {"path" "evidence/authorization.txt"
                           "object" "repo.release"
                           "relation" "zil.publisher"
                           "subject" "agent.release"}
          "formalization" {"path" "evidence/formalization.txt"
                           "required_targets" ["foundations"]}}}]
    {:root root :request request :artifact artifact
     :artifact-sha artifact-sha
     :workflow workflow :proof proof :locks locks}))

(deftest complete-release-evidence-passes-test
  (let [{:keys [root request]} (evidence-fixture)
        first-report (attestation/attest request root)
        second-report (attestation/attest request root)]
    (is (:ok first-report))
    (is (= attestation/attestation-format (:format first-report)))
    (is (= 1 (count (:artifacts first-report))))
    (is (= 5 (count (:evidence first-report))))
    (is (every? #(= :verified (:status %)) (:evidence first-report)))
    (is (empty? (:failures first-report)))
    (is (.startsWith (:attestation_fingerprint first-report) "sha256:"))
    (is (= (:attestation_fingerprint first-report)
           (:attestation_fingerprint second-report)))))

(deftest artifact-hash-mismatch-fails-test
  (let [{:keys [root request]} (evidence-fixture)
        changed (assoc-in request ["artifacts" 0 "sha256"]
                          (str "sha256:" (apply str (repeat 64 "0"))))
        report (attestation/attest changed root)]
    (is (false? (:ok report)))
    (is (= :hash_mismatch (get-in report [:artifacts 0 :status])))
    (is (some #(= :artifact_failure (:kind %)) (:failures report)))))

(deftest theorem-locks-must-use-proof-snapshot-test
  (let [{:keys [root request locks]} (evidence-fixture)
        _ (write-json! root "evidence/locks.json"
                       (assoc locks "current_event_batch_fingerprint"
                              "sha256:different"))
        report (attestation/attest request root)]
    (is (false? (:ok report)))
    (is (some #(= :theorem_lock_event_snapshot_mismatch (:kind %))
              (:failures report)))))

(deftest proof-summary-must-match-resolution-rows-test
  (let [{:keys [root request proof]} (evidence-fixture)
        _ (write-json! root "evidence/proof.json"
                       (assoc proof "resolutions" []))
        report (attestation/attest request root)
        kinds (set (map :kind (:failures report)))]
    (is (false? (:ok report)))
    (is (contains? kinds :proof_resolution_row_count))
    (is (contains? kinds :proof_resolution_incomplete))))

(deftest lock-summary-must-match-result-rows-test
  (let [{:keys [root request locks]} (evidence-fixture)
        _ (write-json! root "evidence/locks.json"
                       (assoc locks "results" []))
        report (attestation/attest request root)]
    (is (false? (:ok report)))
    (is (some #(= :theorem_lock_row_count (:kind %))
              (:failures report)))))

(deftest workflow-must-be-verified-and-bind-artifact-test
  (let [{:keys [root request workflow]} (evidence-fixture)
        _ (write-json! root "evidence/workflow.json"
                       (-> workflow
                           (assoc-in ["verification" "status"] "failed")
                           (assoc "output_sha256" "sha256:wrong")))
        report (attestation/attest request root)
        kinds (set (map :kind (:failures report)))]
    (is (false? (:ok report)))
    (is (contains? kinds :workflow_module_not_verified))
    (is (contains? kinds :workflow_artifact_hash_mismatch))))

(deftest authorization-must-allow-exact-request-test
  (let [{:keys [root request]} (evidence-fixture)
        _ (write! root "evidence/authorization.txt"
                  (str "ZIL-AUTHORIZATION\t1\n"
                       "decision\tdeny\n"
                       "source\tnone\n"
                       "object\trepo.other\n"
                       "relation\tzil.publisher\n"
                       "subject\tagent.release\n"
                       "base-facts\t1\n"
                       "closed-facts\t1\n"
                       "deriving-rules\t\n"))
        report (attestation/attest request root)
        kinds (set (map :kind (:failures report)))]
    (is (false? (:ok report)))
    (is (contains? kinds :authorization_denied))
    (is (contains? kinds :authorization_object_mismatch))))

(deftest required-formalization-targets-must-be-accepted-test
  (let [{:keys [root request]} (evidence-fixture)
        _ (write! root "evidence/formalization.txt"
                  (str "ZIL-FORMALIZATION-PLAN\t1\n"
                       "target\tfoundations\timplemented\t100\tblocked\t\tstatus:implemented\tDemo\tFoundation.lean\tDemo.foundation\n"))
        report (attestation/attest request root)]
    (is (false? (:ok report)))
    (is (some #(= :formalization_target_not_accepted (:kind %))
              (:failures report)))))

(deftest missing-required-formalization-target-fails-test
  (let [{:keys [root request]} (evidence-fixture)
        changed (assoc-in request
                          ["evidence" "formalization" "required_targets"]
                          ["unknown"])
        report (attestation/attest changed root)]
    (is (false? (:ok report)))
    (is (some #(= :formalization_target_missing (:kind %))
              (:failures report)))))

(deftest invalid-nested-request-fields-are-rejected-test
  (let [{:keys [request]} (evidence-fixture)]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"Workflow evidence must name one release artifact"
         (attestation/validate-request!
          (assoc-in request ["evidence" "workflow" "artifact"] "missing.lean"))))
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"unique target IDs"
         (attestation/validate-request!
          (assoc-in request
                    ["evidence" "formalization" "required_targets"]
                    ["foundations" "foundations"]))))))

(deftest evidence-path-escape-is-rejected-test
  (let [{:keys [root request]} (evidence-fixture)
        changed (assoc-in request ["evidence" "proof_tokens" "path"]
                          "../outside.json")]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"escapes request directory"
         (attestation/attest changed root)))))

(deftest attest-file-writes-canonical-json-test
  (let [{:keys [root request]} (evidence-fixture)
        request-file (write-json! root "release.json" request)
        output (io/file root "attestation.json")
        report (attestation/attest-file! (.getPath request-file)
                                         (.getPath output))
        decoded (json/read-str (slurp output))]
    (is (:ok report))
    (is (= attestation/attestation-format (get decoded "format")))
    (is (= "verified" (get-in decoded ["evidence" 0 "status"])))
    (is (= (:attestation_fingerprint report)
           (get decoded "attestation_fingerprint")))))

(deftest workflow-runner-emits-versioned-hashed-report-test
  (let [root (temp-dir)
        output (write! root "Demo.lean" "import Zil.Workflow\n")
        report {:ok true
                :module "Demo"
                :revision "rev:1"
                :complete true
                :action_count 1
                :as_of 150
                :output (.getPath output)
                :namespace "Demo.Generated"
                :verification {:status :verified}}
        document (workflow-runner/workflow-document report)]
    (is (= workflow-runner/workflow-format (get document "format")))
    (is (= "verified" (get-in document ["verification" "status"])))
    (is (= (attestation/file-sha256 output)
           (get document "output_sha256")))))
