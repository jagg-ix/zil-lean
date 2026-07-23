(ns zil.port-native-macro-test
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.core :as core]
            [zil.port.native-macro :as native-macro]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-native-macro-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(def library-a
  (str "mAcRo grant(object, subject): // mixed-case control\n"
       "eMiT {{object}}#viewer@{{subject}}. // extension fact\n"
       "eNdMaCrO.\n"))

(def library-b
  (str "MACRO grant_platform(object):\n"
       "EMIT USE grant({{object}}, team:platform).\n"
       "ENDMACRO.\n"))

(def model-source
  (str "MODULE macro.parity.\n"
       "USE grant_platform(doc:readme).\n"
       "QUERY viewers:\n"
       "FIND ?subject WHERE doc:readme#viewer@?subject.\n"))

(defn- fixture []
  (let [root (temp-dir)
        model (write! root "project/models/access.zc" model-source)
        _ (write! root "project/lib/20-wrapper.zc" library-b)
        _ (write! root "project/lib/10-grant.zc" library-a)]
    {:root root :model model}))

(defn- source-path [command]
  (first (filter #(str/ends-with? % ".zc") command)))

(defn- parity-runner [calls]
  (fn [request]
    (let [command (:command request)
          source (slurp (source-path command))
          expanded (core/expand-macros source)]
      (swap! calls conj {:command command :source source})
      {:exit 0
       :out (str (str/join "\n" expanded) "\n")
       :err ""
       :command command})))

(deftest discovers-nearest-library-in-sorted-order-test
  (let [{:keys [model]} (fixture)
        composition (native-macro/compose-model (.getPath model) {})
        names (mapv #(.getName (io/file %)) (:lib_files composition))]
    (is (= ["10-grant.zc" "20-wrapper.zc"] names))
    (is (str/includes? (:text composition) "begin lib/10-grant.zc"))
    (is (< (.indexOf (:text composition) "MACRO grant")
           (.indexOf (:text composition) "MACRO grant_platform")))
    (is (< (.indexOf (:text composition) "MACRO grant_platform")
           (.indexOf (:text composition) "MODULE macro.parity")))))

(deftest explicit-library-directory-overrides-nearest-test
  (let [{:keys [root model]} (fixture)
        explicit (io/file root "alternative-lib")
        _ (write! explicit "only.zc"
                  (str "MACRO direct(object):\n"
                       "EMIT {{object}}#owner@team:direct.\n"
                       "ENDMACRO.\n"))
        composition (native-macro/compose-model
                     (.getPath model) {:lib-dir (.getPath explicit)})]
    (is (= ["only.zc"]
           (mapv #(.getName (io/file %)) (:lib_files composition))))
    (is (str/includes? (:text composition) "MACRO direct"))
    (is (not (str/includes? (:text composition) "MACRO grant_platform")))))

(deftest native-parity-report-matches-clojure-expansion-test
  (let [{:keys [model]} (fixture)
        calls (atom [])
        report (native-macro/parity-report
                {:model (.getPath model)
                 :native-command ["fake-zil"]
                 :runner (parity-runner calls)})]
    (is (:ok report))
    (is (:exact report))
    (is (= (:legacy_count report) (:native_count report)))
    (is (empty? (:legacy_only report)))
    (is (empty? (:native_only report)))
    (is (= 1 (count @calls)))
    (is (= ["fake-zil" "expand"]
           (subvec (vec (:command (first @calls))) 0 2)))
    (is (= 64 (count (:source_sha256 report))))))

(deftest parity-report-surfaces-native-differences-test
  (let [{:keys [model]} (fixture)
        report (native-macro/parity-report
                {:model (.getPath model)
                 :native-command ["fake-zil"]
                 :runner (fn [request]
                           {:exit 0
                            :out "MODULE macro.parity.\ndoc:other#viewer@team:platform.\n"
                            :err ""
                            :command (:command request)})})]
    (is (false? (:ok report)))
    (is (false? (:exact report)))
    (is (seq (:legacy_only report)))
    (is (seq (:native_only report)))))

(deftest macro-compile-writes-native-output-test
  (let [{:keys [root model]} (fixture)
        output (io/file root "generated/Access.lean")
        calls (atom [])
        report (native-macro/compile-model!
                {:model (.getPath model)
                 :output (.getPath output)
                 :namespace "Project.Generated.Access"
                 :native-command ["fake-zil"]
                 :runner (fn [request]
                           (let [command (:command request)]
                             (swap! calls conj command)
                             {:exit 0
                              :out "import Zil\nnamespace Project.Generated.Access\nend Project.Generated.Access\n"
                              :err ""
                              :command command}))})]
    (is (:ok report))
    (is (.exists output))
    (is (str/includes? (slurp output) "namespace Project.Generated.Access"))
    (is (= "Project.Generated.Access" (last (first @calls))))
    (is (= "compile" (second (first @calls))))))

(deftest macro-expand-writes-expanded-output-test
  (let [{:keys [root model]} (fixture)
        output (io/file root "generated/access.expanded.zc")
        report (native-macro/expand-model!
                {:model (.getPath model)
                 :output (.getPath output)
                 :native-command ["fake-zil"]
                 :runner (parity-runner (atom []))})]
    (is (:ok report))
    (is (str/includes? (slurp output)
                       "doc:readme#viewer@team:platform."))))

(deftest native-failure-is-not-silently-accepted-test
  (let [{:keys [model]} (fixture)]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"Native macro compilation failed"
         (native-macro/compile-model!
          {:model (.getPath model)
           :output (str (.getPath model) ".lean")
           :native-command ["fake-zil"]
           :runner (fn [request]
                     {:exit 1 :out "" :err "unknown macro"
                      :command (:command request)})})))))
