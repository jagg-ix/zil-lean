(ns zil.port-gate-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is]]
            [zil.port.gate :as gate]
            [zil.port.gate-runner :as runner]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-port-gate-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- fixture-source []
  (str "MODULE complete.port.\n"
       "MACRO addFact(x):\n"
       "EMIT {{x}}#owner@user:1.\n"
       "ENDMACRO.\n"
       "USE addFact(doc:a).\n"
       "doc:a#viewer@group:eng#member [source=manual].\n"
       "RULE active:\n"
       "IF ?doc#viewer@?user AND NOT ?doc#blocked@?user\n"
       "THEN ?doc#active@?user.\n"
       "QUERY activeUsers:\n"
       "FIND ?user WHERE doc:a#active@?user.\n"
       "SERVICE db [env=prod].\n"
       "TM_ATOM tm [states=#{q0 qa qr}, alphabet=#{0 _}, blank=_, initial=q0, "
       "accept=#{qa}, reject=#{qr}, transitions={[q0 _] [qa _ :N]}].\n"
       "LTS_ATOM lts [states=#{s0 s1}, initial=s0, transitions={[s0 go] [s1]}].\n"))

(defn- write-source! [root]
  (let [file (io/file root "complete.zc")]
    (.mkdirs (.getParentFile file))
    (spit file (fixture-source))
    file))

(defn- reports [source root compile-status conformance-status]
  (let [path (.getCanonicalPath source)
        root-path (.getCanonicalPath root)]
    [{:schema "ZIL-LIBRARY-MANIFEST/1"
      :roots [root-path]
      :entries [{:source path
                 :root root-path
                 :relative "complete.zc"
                 :status compile-status}]}
     {:schema "ZIL-CONFORMANCE/1"
      :entries [{:source path
                 :status conformance-status
                 :ok (= :pass conformance-status)}]}]))

(deftest classifies-major-language-features-test
  (let [features (gate/source-features (fixture-source))]
    (doseq [feature [:facts :attributes :usersets :rules :negation :queries
                     :macros :declarations :tm-atoms :lts-atoms]]
      (is (contains? features feature) (str "missing " feature)))))

(deftest complete-corpus-passes-strict-default-gate-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        source (write-source! root)
        [manifest conformance] (reports source root :compiled :pass)
        result (runner/evaluate manifest conformance {}
                                {:file-exists? (constantly true)})]
    (is (:ok result))
    (is (= 1.0 (get-in result [:global :compile-ratio])))
    (is (= 1.0 (get-in result [:global :exact-ratio])))
    (is (every? :retirable (vals (:components result))))
    (is (= 1 (get-in result [:features :macros])))
    (is (= 1 (get-in result [:features :tm-atoms])))))

(deftest mismatch-blocks-global-and-component-retirement-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        source (write-source! root)
        [manifest conformance] (reports source root :compiled :mismatch)
        result (runner/evaluate manifest conformance {}
                                {:file-exists? (constantly true)})]
    (is (false? (:ok result)))
    (is (= 1 (get-in result [:global :mismatch])))
    (is (some #(= :mismatch (:kind %)) (:failures result)))
    (is (false? (get-in result [:components :library-corpus :retirable])))))

(deftest missing-conformance-entry-is-explicit-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        source (write-source! root)
        path (.getCanonicalPath source)
        manifest {:schema "ZIL-LIBRARY-MANIFEST/1"
                  :roots [(.getCanonicalPath root)]
                  :entries [{:source path :root (.getCanonicalPath root)
                             :relative "complete.zc" :status :compiled}]}
        conformance {:schema "ZIL-CONFORMANCE/1" :entries []}
        result (runner/evaluate manifest conformance {}
                                {:file-exists? (constantly true)})]
    (is (false? (:ok result)))
    (is (= 1 (get-in result [:global :missing-conformance])))
    (is (= :missing (get-in result [:records 0 :conformance-status])))))

(deftest missing-revision-evidence-blocks-only-that-component-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        source (write-source! root)
        [manifest conformance] (reports source root :compiled :pass)
        result (runner/evaluate manifest conformance {}
                                {:file-exists? (constantly false)})]
    (is (false? (:ok result)))
    (is (false? (get-in result [:components :revision-causal :retirable])))
    (is (seq (get-in result [:components :revision-causal :failures])))
    (is (true? (get-in result [:components :macro-frontend :retirable])))))

(deftest required-root-must-appear-in-manifest-test
  (let [workspace (temp-dir)
        root (io/file workspace "lib")
        missing (io/file workspace "libsets")
        source (write-source! root)
        [manifest conformance] (reports source root :compiled :pass)
        result (runner/evaluate manifest conformance
                                {:required-roots [(.getPath missing)]}
                                {:file-exists? (constantly true)})]
    (is (false? (:ok result)))
    (is (some #(= :missing-required-root (:kind %)) (:failures result)))))

(deftest check-status-counts-as-successful-compilation-test
  (let [workspace (temp-dir)
        root (io/file workspace "examples")
        source (write-source! root)
        [manifest conformance] (reports source root :checked :pass)
        result (runner/evaluate manifest conformance {}
                                {:file-exists? (constantly true)})]
    (is (:ok result))
    (is (= 1 (get-in result [:global :compiled])))))

(deftest config-merge-replaces-vectors-and-deep-merges-components-test
  (let [merged (runner/merge-config
                {:required-roots ["custom"]
                 :global {:max-mismatch 2}
                 :components {:macro-frontend {:min-sources 3}}})]
    (is (= ["custom"] (:required-roots merged)))
    (is (= 2 (get-in merged [:global :max-mismatch])))
    (is (= 1.0 (get-in merged [:global :min-compile-ratio])))
    (is (= 3 (get-in merged [:components :macro-frontend :min-sources])))
    (is (= #{:macros}
           (get-in merged [:components :macro-frontend :features])))))
