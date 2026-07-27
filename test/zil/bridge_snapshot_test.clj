(ns zil.bridge-snapshot-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.bridge.snapshot :as snapshot]))

(defn- tmp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-snapshot" (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest deterministic-snapshot-and-lean-module-test
  (let [dir (tmp-dir)
        model (java.io.File. dir "model.zc")
        json-out (java.io.File. dir "snapshot.json")
        lean-out (java.io.File. dir "Snapshot.lean")]
    (spit model "MODULE knowledge.demo.\napp:svc1#depends_on@service:db1.\nservice:db1#available@true.\nRULE dependencyAvailability:\nIF ?app#depends_on@?dep AND ?dep#available@true\nTHEN ?app#dependency_available@?dep.\n")
    (let [a (snapshot/compile-snapshot (.getPath model))
          b (snapshot/compile-snapshot (.getPath model))
          report (snapshot/export-snapshot!
                  (.getPath model)
                  {:json-output (.getPath json-out) :lean-output (.getPath lean-out)})]
      (is (= a b))
      (is (= "complete" (:completeness report)))
      (is (= 2 (:fact_count report)))
      (is (= 1 (:rule_count report)))
      (is (re-find #"zil.snapshot.v0.2" (slurp json-out)))
      (is (re-find #"module\s+public import Zil" (slurp lean-out)))
      (is (re-find #"def snapshotRevision" (slurp lean-out)))
      (is (re-find #"zil_snapshot.*completeness complete" (slurp lean-out)))
      (is (re-find #"zil_fact.*depends_on" (slurp lean-out)))
      (is (re-find #"literals := \[\.positive" (slurp lean-out)))
    (is (not (re-find #"body := \[\]" (slurp lean-out))))
    (is (re-find #"literals := \[\.positive" (slurp lean-out)))
      (is (re-find #"def program : Program" (slurp lean-out))))))

(deftest attributes-and-stratified-negation-round-trip-test
  (let [dir (tmp-dir)
        model (java.io.File. dir "negation.zc")]
    (spit model "MODULE knowledge.negative.\na#r@b [quality=reviewed, score=5].\nRULE noS:\nIF ?x#r@?y [quality=?quality] AND NOT ?x#s@?y [reason=blocked]\nTHEN ?x#t@?y [quality=?quality].\n")
    (let [compiled (snapshot/compile-snapshot (.getPath model))
          json-text (snapshot/render-json compiled)
          lean-text (snapshot/render-lean compiled "Zil.Generated.Negation")]
      (is (= "zil.snapshot.v0.2" (get compiled "format")))
      (is (= "stratified-attributes-v0.2" (get compiled "profile")))
      (is (re-find #"\"attrs\"" json-text))
      (is (re-find #"\"polarity\":\"negative\"" json-text))
      (is (re-find #"quality = \?quality" lean-text))
      (is (re-find #"NOT .* # s @" lean-text))
      (is (re-find #"\.negative" lean-text)))))

(deftest unsupported-nonscalar-attribute-fails-closed-test
  (let [dir (tmp-dir)
        model (java.io.File. dir "nested.zc")]
    (spit model "MODULE knowledge.nested.\na#r@b [meta={:nested [1 2]}].\n")
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"outside the native Lean scalar core"
                          (snapshot/compile-snapshot (.getPath model))))))
