(ns zil.port-library-test
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [zil.port.library :as library]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-library-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (.mkdirs (.getParentFile file))
    (spit file content)
    file))

(deftest deterministic-plan-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        out (io/file workspace "generated")
        _ (write! root "z-last.zc" "doc:z#owner@user:1.\n")
        _ (write! root "nested/a-first.zc" "doc:a#owner@user:2.\n")
        entries (library/plan {:roots [(.getPath root)]
                               :output-root (.getPath out)
                               :namespace-prefix "Project.Generated"})]
    (is (= ["nested/a-first.zc" "z-last.zc"]
           (mapv :relative entries)))
    (is (= ["Project.Generated.Lib.Nested.AFirst"
            "Project.Generated.Lib.ZLast"]
           (mapv :namespace entries)))
    (is (str/ends-with? (:output (first entries))
                        "generated/Lib/Nested/AFirst.lean"))
    (is (= 64 (count (:source-sha256 (first entries)))))))

(deftest rejects-output-and-namespace-collisions-test
  (let [workspace (temp-dir)
        root-a (io/file workspace "one/lib")
        root-b (io/file workspace "two/lib")
        out (io/file workspace "generated")]
    (write! root-a "same.zc" "doc:a#owner@user:1.\n")
    (write! root-b "same.zc" "doc:b#owner@user:2.\n")
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"contains collisions"
         (library/plan {:roots [(.getPath root-a) (.getPath root-b)]
                        :output-root (.getPath out)})))))

(deftest compiles-with-captured-native-output-test
  (let [workspace (temp-dir)
        root (io/file workspace "models")
        out (io/file workspace "generated")
        manifest (io/file workspace "manifest.edn")
        source (write! root "access.zc" "doc:readme#owner@user:10.\n")
        calls (atom [])
        runner (fn [command]
                 (swap! calls conj command)
                 {:exit 0
                  :out "import Zil\n\nnamespace Project.Generated.Models.Access\nend Project.Generated.Models.Access\n"
                  :err ""
                  :command command})
        report (library/compile-tree!
                {:roots [(.getPath root)]
                 :output-root (.getPath out)
                 :manifest (.getPath manifest)
                 :namespace-prefix "Project.Generated"
                 :command ["fake-zil" "compile"]
                 :runner runner})
        entry (first (:entries report))
        invocation (first @calls)
        manifest-data (edn/read-string (slurp manifest))]
    (is (:ok report))
    (is (= :compiled (:status entry)))
    (is (.exists (io/file (:output entry))))
    (is (= "fake-zil" (nth invocation 0)))
    (is (= "compile" (nth invocation 1)))
    (is (= (.getCanonicalPath source) (nth invocation 2)))
    (is (= "-" (nth invocation 3)))
    (is (= (:namespace entry) (nth invocation 4)))
    (is (= "ZIL-LIBRARY-MANIFEST/1" (:schema manifest-data)))
    (is (= (:output-sha256 entry)
           (:output-sha256 (first (:entries manifest-data)))))))

(deftest check-only-does-not-write-generated-module-test
  (let [workspace (temp-dir)
        root (io/file workspace "libsets")
        out (io/file workspace "generated")
        manifest (io/file workspace "manifest.edn")
        _ (write! root "policy.zc" "doc:p#viewer@user:1.\n")
        report (library/compile-tree!
                {:roots [(.getPath root)]
                 :output-root (.getPath out)
                 :manifest (.getPath manifest)
                 :check-only true
                 :runner (fn [command]
                           {:exit 0 :out "import Zil\n" :err "" :command command})})
        entry (first (:entries report))]
    (is (:ok report))
    (is (= :checked (:status entry)))
    (is (not (.exists (io/file (:output entry)))))
    (is (.exists manifest))))

(deftest records-native-compiler-failures-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        manifest (io/file workspace "manifest.edn")
        _ (write! root "broken.zc" "not valid\n")
        report (library/compile-tree!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath manifest)
                 :runner (fn [command]
                           {:exit 1 :out "" :err "line 1: invalid source" :command command})})]
    (is (false? (:ok report)))
    (is (= :failed (:status (first (:entries report)))))
    (is (= "line 1: invalid source" (:error (first (:entries report)))))))
