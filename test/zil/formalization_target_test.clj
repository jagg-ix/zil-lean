(ns zil.formalization-target-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.core :as core]
            [zil.formalization.target :as target]))

(def model
  "MODULE demo.targets.\nFORMALIZATION_TARGET base [module=Demo.Base, file=Demo/Base.lean, declaration=Demo.Base.done, status=proved, priority=10].\nFORMALIZATION_TARGET next [module=Demo.Next, file=Demo/Next.lean, declaration=Demo.Next.done, status=ready, priority=100, dependencies=[\"base\"]].\n")

(defn- temp-dir []
  (let [file (java.io.File/createTempFile "zil-formalization-" "")]
    (.delete file) (.mkdirs file) file))

(deftest language-construction-and-next-selection-test
  (let [path (java.io.File/createTempFile "zil-targets-" ".zc")]
    (spit path model)
    (is (= :formalization_target
           (:kind (second (:declarations (core/compile-program model))))))
    (is (= "next" (:id (target/next-target (.getPath path)))))))

(deftest invalid-target-graph-is-rejected-test
  (let [path (java.io.File/createTempFile "zil-target-cycle-" ".zc")]
    (spit path
          "MODULE cycle.\nFORMALIZATION_TARGET a [module=A, file=A.lean, declaration=A.done, status=ready, priority=1, dependencies=[\"b\"]].\nFORMALIZATION_TARGET b [module=B, file=B.lean, declaration=B.done, status=ready, priority=1, dependencies=[\"a\"]].\n")
    (is (thrown-with-msg? clojure.lang.ExceptionInfo #"graph has a cycle"
                          (target/load-targets (.getPath path))))))

(deftest local-lean-target-check-test
  (let [root (temp-dir) dir (java.io.File. root "Demo") _ (.mkdirs dir)
        lean (java.io.File. dir "Next.lean") model-file (java.io.File. root "targets.zc")]
    (spit lean "namespace Demo.Next\nlemma done : 1 = 1 := by rfl\nend Demo.Next\n")
    (spit model-file model)
    (is (:ok (target/check-target (.getPath model-file) "next" (.getPath root)
                                  (fn [_ file] (if (= "Demo/Next.lean" file) 0 1)))))
    (testing "the declaration contract cannot silently drift"
      (spit lean "namespace Demo.Next\nlemma renamed : 1 = 1 := by rfl\nend Demo.Next\n")
      (is (thrown-with-msg? clojure.lang.ExceptionInfo #"source checks"
                            (target/check-target (.getPath model-file) "next" (.getPath root)
                                                 (fn [_ _] 0)))))))
