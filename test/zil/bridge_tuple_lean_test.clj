(ns zil.bridge-tuple-lean-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.tuple-lean :as tuple-lean]))

(defn- tmp-dir
  []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-tuple-lean"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(def access-tuples
  "doc:readme#owner@user:10.
 group:eng#member@user:11.
 doc:readme#viewer@group:eng#member.
 doc:readme#parent@folder:A.
 ")

(deftest exports-original-tuple-syntax-to-native-zil-lean-test
  (let [dir (tmp-dir)
        input (java.io.File. dir "access.zc")]
    (spit input access-tuples)
    (let [report (tuple-lean/export-tuples->lean4 (.getAbsolutePath input))
          text (:text report)]
      (is (:ok report))
      (is (= 4 (:fact_count report)))
      (is (= 1 (:userset_rule_count report)))
      (is (= "Zil.Generated.Access" (:namespace report)))
      (is (str/includes? text "import Zil"))
      (is (str/includes? text "node(doc.readme)"))
      (is (str/includes? text "node(user.u10)"))
      (is (str/includes? text "node(group.eng)"))
      (is (str/includes? text "node(user.u11)"))
      (is (str/includes? text "node(folder.A)"))
      (is (str/includes? text "zil_theorem_rule viewerViaMember"))
      (is (str/includes? text "hInner : userset ⟶[member] subject"))
      (is (str/includes? text ": object ⟶[viewer] subject")))))

(deftest exports-to-file-with-requested-namespace-test
  (let [dir (tmp-dir)
        input (java.io.File. dir "access.zc")
        output (java.io.File. dir "generated/Access.lean")]
    (spit input access-tuples)
    (let [report (tuple-lean/export-tuples->lean4
                  (.getAbsolutePath input)
                  {:output-path (.getAbsolutePath output)
                   :namespace "Project.AccessFacts"})
          text (slurp output)]
      (is (.exists output))
      (is (= "Project.AccessFacts" (:namespace report)))
      (is (str/includes? text "namespace Project.AccessFacts"))
      (is (str/includes? text "end Project.AccessFacts")))))

(deftest preserves-existing-lean-name-segments-test
  (testing "dots and case remain available for Lean declaration names"
    (is (= "lean.Parser.parse"
           (tuple-lean/term->lean-name "lean.Parser.parse"))))
  (testing "numeric user identifiers receive a valid Lean segment"
    (is (= "user.u42"
           (tuple-lean/term->lean-name "user:42")))))

(deftest rejects-attributes-until-they-have-a-native-encoding-test
  (let [dir (tmp-dir)
        input (java.io.File. dir "attrs.zc")]
    (spit input "doc:readme#owner@user:10 [source=manual].\n")
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"attributes do not yet have a native"
         (tuple-lean/export-tuples->lean4 (.getAbsolutePath input))))))
