(ns zil.preprocess-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.preprocess :as zp]))

(defn- tmp-dir
  []
  (.toFile
   (java.nio.file.Files/createTempDirectory
    "zil-preprocess"
    (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest preprocess-auto-discovers-lib-test
  (let [root (tmp-dir)
        lib-dir (java.io.File. root "lib")
        models-dir (java.io.File. root "models")
        _ (.mkdirs lib-dir)
        _ (.mkdirs models-dir)
        lib-a (java.io.File. lib-dir "a.zc")
        lib-b (java.io.File. lib-dir "b.zc")
        model (java.io.File. models-dir "main.zc")]
    (spit lib-b "MODULE lib.b.\n")
    (spit lib-a "MODULE lib.a.\n")
    (spit model "MODULE app.main.\n")
    (let [report (zp/preprocess-model (.getAbsolutePath model) {})
          text (:text report)]
      (is (:ok report))
      (is (= [(.getAbsolutePath lib-a) (.getAbsolutePath lib-b)]
             (:lib_files report)))
      (is (str/includes? text "// ---- begin lib/a.zc ----"))
      (is (str/includes? text "// ---- begin lib/b.zc ----"))
      (is (str/includes? text "// ---- begin main.zc ----"))
      (is (< (.indexOf text "lib/a.zc")
             (.indexOf text "lib/b.zc")
             (.indexOf text "main.zc"))))))

(deftest preprocess-explicit-lib-dir-test
  (let [root (tmp-dir)
        lib-dir (java.io.File. root "lib")
        custom-lib (java.io.File. root "custom-lib")
        _ (.mkdirs lib-dir)
        _ (.mkdirs custom-lib)
        _ (spit (java.io.File. lib-dir "ignored.zc") "MODULE ignored.\n")
        selected (java.io.File. custom-lib "selected.zc")
        model (java.io.File. root "model.zc")]
    (spit selected "MODULE selected.\n")
    (spit model "MODULE app.main.\n")
    (let [report (zp/preprocess-model (.getAbsolutePath model)
                                      {:lib-dir (.getAbsolutePath custom-lib)})]
      (is (= [(.getAbsolutePath selected)] (:lib_files report)))
      (is (str/includes? (:text report) "lib/selected.zc"))
      (is (not (str/includes? (:text report) "ignored.zc"))))))

(deftest preprocess-writes-output-path-test
  (let [root (tmp-dir)
        lib-dir (java.io.File. root "lib")
        _ (.mkdirs lib-dir)
        _ (spit (java.io.File. lib-dir "a.zc") "MODULE lib.a.\n")
        model (java.io.File. root "model.zc")
        out (java.io.File. root "model.pre.zc")]
    (spit model "MODULE app.main.\n")
    (let [report (zp/preprocess-model (.getAbsolutePath model)
                                      {:output-path (.getAbsolutePath out)})]
      (is (.exists out))
      (is (= (.getAbsolutePath out) (:output_path report)))
      (is (str/includes? (slurp out) "lib/a.zc")))))
