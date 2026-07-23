(ns zil.port-conformance-test
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [zil.port.conformance :as conformance]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-conformance-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(defn- temp-file [name content]
  (write! (temp-dir) name content))

(defn- source-path [command]
  (first (filter #(str/ends-with? % ".zc") command)))

(def simple-source
  (str "MODULE demo.access.\n"
       "doc:a#parent@doc:b.\n"
       "RULE inherit:\n"
       "IF ?x#parent@?y\n"
       "THEN ?x#ancestor@?y.\n"
       "QUERY ancestors:\n"
       "FIND ?y WHERE doc:a#ancestor@?y.\n"))

(defn- oracle-runner [source]
  (fn [command]
    (case (second command)
      "conformance" {:exit 0
                     :out (conformance/legacy-report source)
                     :err ""
                     :command command}
      "expand" {:exit 0
                :out (conformance/legacy-expanded source)
                :err ""
                :command command}
      {:exit 2 :out "" :err "unknown operation" :command command})))

(defn- source-oracle-runner [calls]
  (fn [command]
    (let [operation (second command)
          path (source-path command)
          source (slurp path)]
      (swap! calls conj {:operation operation :path path :source source})
      (case operation
        "conformance" {:exit 0
                       :out (conformance/legacy-report source)
                       :err ""
                       :command command}
        "expand" {:exit 0
                  :out (conformance/legacy-expanded source)
                  :err ""
                  :command command}
        {:exit 2 :out "" :err "unknown operation" :command command}))))

(deftest legacy-report-is-deterministic-test
  (let [first-report (conformance/legacy-report simple-source)
        second-report (conformance/legacy-report simple-source)]
    (is (= first-report second-report))
    (is (str/starts-with? first-report "ZILC\t1\nmodule\tdemo.access\n"))
    (is (some #(str/starts-with? % "closed\t")
              (str/split-lines first-report)))
    (is (some #(str/starts-with? % "query-row\tancestors\t")
              (str/split-lines first-report)))))

(deftest exact-oracle-parity-test
  (let [file (temp-file "simple.zc" simple-source)
        result (conformance/compare-file
                {:runner (oracle-runner simple-source)
                 :command ["fake"]}
                file)]
    (is (:ok result))
    (is (= :pass (:status result)))
    (is (:expansion-equal result))
    (is (false? (:macro-composed result)))
    (is (= (:source-sha256 result) (:compiled-source-sha256 result)))
    (is (empty? (:differences result)))))

(deftest library-backed-model-uses-one-composed-source-test
  (let [workspace (temp-dir)
        project (io/file workspace "project")
        _ (write! project "lib/10-grant.zc"
                  (str "mAcRo grant(object, subject):\n"
                       "eMiT {{object}}#viewer@{{subject}}.\n"
                       "eNdMaCrO.\n"))
        model (write! project "models/access.zc"
                      (str "MODULE macro.access.\n"
                           "USE grant(doc:readme, user:11).\n"
                           "QUERY viewers:\n"
                           "FIND ?user WHERE doc:readme#viewer@?user.\n"))
        calls (atom [])
        result (conformance/compare-file
                {:runner (source-oracle-runner calls)
                 :command ["fake"]}
                model)]
    (is (:ok result))
    (is (= :pass (:status result)))
    (is (:macro-composed result))
    (is (= ["10-grant.zc"]
           (mapv #(.getName (io/file %)) (:lib-files result))))
    (is (not= (:source-sha256 result) (:compiled-source-sha256 result)))
    (is (= #{"conformance" "expand"} (set (map :operation @calls))))
    (is (every? #(str/includes? (:source %) "MACRO grant") @calls))
    (is (every? #(str/includes? (:source %) "MODULE macro.access") @calls))
    (is (every? #(not= (.getCanonicalPath model) (:path %)) @calls))))

(deftest reports-section-level-mismatch-test
  (let [file (temp-file "mismatch.zc" simple-source)
        expected (conformance/legacy-report simple-source)
        runner (fn [command]
                 (case (second command)
                   "conformance" {:exit 0
                                  :out (str/replace expected "zil.ancestor" "zil.changed")
                                  :err ""
                                  :command command}
                   "expand" {:exit 0
                             :out (conformance/legacy-expanded simple-source)
                             :err ""
                             :command command}))
        result (conformance/compare-file {:runner runner :command ["fake"]} file)]
    (is (false? (:ok result)))
    (is (= :mismatch (:status result)))
    (is (or (contains? (:differences result) "closed")
            (contains? (:differences result) "query")))))

(deftest expansion-mismatch-is-independent-test
  (let [file (temp-file "expansion.zc" simple-source)
        runner (fn [command]
                 (case (second command)
                   "conformance" {:exit 0
                                  :out (conformance/legacy-report simple-source)
                                  :err ""
                                  :command command}
                   "expand" {:exit 0 :out "different\n" :err "" :command command}))
        result (conformance/compare-file {:runner runner :command ["fake"]} file)]
    (is (false? (:ok result)))
    (is (false? (:expansion-equal result)))
    (is (empty? (:differences result)))))

(deftest accepts-shared-rejection-test
  (let [source "this is invalid\n"
        file (temp-file "invalid.zc" source)
        runner (fn [command]
                 {:exit 1 :out "" :err "line 1: invalid source" :command command})
        result (conformance/compare-file {:runner runner :command ["fake"]} file)]
    (is (:ok result))
    (is (= :both-rejected (:status result)))))

(deftest userset-lowering-enters-legacy-semantic-report-test
  (let [source (str "MODULE usersets.\n"
                    "group:eng#member@user:11.\n"
                    "doc:readme#viewer@group:eng#member.\n"
                    "QUERY viewers:\n"
                    "FIND ?u WHERE doc:readme#viewer@?u.\n")
        report (conformance/legacy-report source)]
    (is (str/includes? report "node:group.eng"))
    (is (str/includes? report "node:user.u11"))
    (is (str/includes? report "query-row\tviewers\tu=node:user.u11"))))
