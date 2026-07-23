(ns zil.port-conformance-test
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [zil.port.conformance :as conformance]))

(defn- temp-file [name content]
  (let [dir (.toFile (java.nio.file.Files/createTempDirectory
                      "zil-conformance-test"
                      (make-array java.nio.file.attribute.FileAttribute 0)))
        file (io/file dir name)]
    (spit file content)
    file))

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
    (let [operation (nth command (- (count command) 2))]
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
    (is (empty? (:differences result)))))

(deftest reports-section-level-mismatch-test
  (let [file (temp-file "mismatch.zc" simple-source)
        expected (conformance/legacy-report simple-source)
        runner (fn [command]
                 (let [operation (nth command (- (count command) 2))]
                   (case operation
                     "conformance" {:exit 0
                                    :out (str/replace expected "zil.ancestor" "zil.changed")
                                    :err ""
                                    :command command}
                     "expand" {:exit 0
                               :out (conformance/legacy-expanded simple-source)
                               :err ""
                               :command command})))
        result (conformance/compare-file {:runner runner :command ["fake"]} file)]
    (is (false? (:ok result)))
    (is (= :mismatch (:status result)))
    (is (or (contains? (:differences result) "closed")
            (contains? (:differences result) "query")))))

(deftest expansion-mismatch-is-independent-test
  (let [file (temp-file "expansion.zc" simple-source)
        runner (fn [command]
                 (let [operation (nth command (- (count command) 2))]
                   (case operation
                     "conformance" {:exit 0
                                    :out (conformance/legacy-report simple-source)
                                    :err ""
                                    :command command}
                     "expand" {:exit 0 :out "different\n" :err "" :command command})))
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
