(ns zil.port-retirement-test
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [zil.port.retirement :as retirement]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-retirement-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(def ready-gate
  {:schema "ZIL-PORT-GATE/1"
   :ok true
   :components {:runtime {:retirable true}}})

(def active-gate
  {:schema "ZIL-PORT-GATE/1"
   :ok false
   :components {:runtime {:retirable false}}})

(def verified
  {:schema "ZIL-LEAN-VERIFY/1"
   :ok true
   :aggregate {:status :verified}})

(def embedded
  {:schema "ZIL-EMBEDDED-MANIFEST/1"
   :ok true
   :block-count 2})

(defn- policy [root]
  (doseq [relative ["src" "test" "docs"]]
    (.mkdirs (io/file root relative)))
  {:repository-root (.getPath root)
   :scan-roots ["src" "test" "docs"]
   :non-blocking-prefixes ["test/" "docs/"]
   :components
   {:legacy-runtime
    {:gate-components [:runtime]
     :require-verification true
     :require-aggregate true
     :require-embedded true
     :min-embedded-blocks 1
     :patterns [{:id :legacy-api :pattern "zil\\.cli"}]
     :allow-paths ["src/zil/cli.clj"]}}})

(deftest unauthorized-production-consumer-freezes-component-test
  (let [root (temp-dir)
        _ (write! root "src/zil/cli.clj" "(ns zil.cli)\n")
        _ (write! root "src/app.clj" "(ns app (:require [zil.cli :as legacy]))\n")
        _ (write! root "docs/legacy.md" "Use zil.cli for old workflows.\n")
        report (retirement/evaluate ready-gate verified embedded (policy root))
        component (get-in report [:components :legacy-runtime])
        blocker (first (filter :blocking (:consumers component)))]
    (is (false? (:ok report)))
    (is (= :frozen (:state component)))
    (is (= 1 (:blocking-consumer-count component)))
    (is (= "src/app.clj" (:path blocker)))
    (is (some :non-blocking (:consumers component)))))

(deftest owned-implementation-and-doc-references-allow-removal-test
  (let [root (temp-dir)
        _ (write! root "src/zil/cli.clj" "(ns zil.cli)\n")
        _ (write! root "docs/legacy.md" "Use zil.cli only for compatibility.\n")
        _ (write! root "test/legacy_test.clj" "(require 'zil.cli)\n")
        report (retirement/evaluate ready-gate verified embedded (policy root))
        component (get-in report [:components :legacy-runtime])]
    (is (:ok report))
    (is (= :ready-to-remove (:state component)))
    (is (zero? (:blocking-consumer-count component)))
    (is (= [:legacy-runtime] (:ready-to-remove report)))))

(deftest missing-evidence-keeps-component-active-test
  (let [root (temp-dir)
        _ (write! root "src/zil/cli.clj" "(ns zil.cli)\n")
        report (retirement/evaluate active-gate verified embedded (policy root))
        component (get-in report [:components :legacy-runtime])]
    (is (:ok report))
    (is (= :active (:state component)))
    (is (false? (:evidence-ok component)))
    (is (= :gate-components-not-retirable
           (get-in component [:evidence-failures 0 :kind])))))

(deftest aggregate-and-embedded-evidence-are-required-test
  (let [root (temp-dir)
        _ (write! root "src/zil/cli.clj" "(ns zil.cli)\n")
        bad-verification (assoc verified :aggregate {:status :blocked})
        bad-embedded (assoc embedded :block-count 0)
        report (retirement/evaluate ready-gate bad-verification bad-embedded
                                    (policy root))
        failures (set (map :kind
                           (get-in report
                                   [:components :legacy-runtime :evidence-failures])))]
    (is (= :active (get-in report [:components :legacy-runtime :state])))
    (is (contains? failures :aggregate-not-verified))
    (is (contains? failures :embedded-block-coverage))))

(deftest run-guard-require-ready-writes-failing-report-test
  (let [root (temp-dir)
        _ (write! root "src/zil/cli.clj" "(ns zil.cli)\n")
        gate-file (write! root "gate.edn" (str (pr-str active-gate) "\n"))
        verification-file (write! root "verification.edn" (str (pr-str verified) "\n"))
        embedded-file (write! root "embedded.edn" (str (pr-str embedded) "\n"))
        policy-file (write! root "policy.edn" (str (pr-str (policy root)) "\n"))
        output (io/file root "retirement.edn")
        report (retirement/run-guard!
                {:gate (.getPath gate-file)
                 :verification (.getPath verification-file)
                 :embedded (.getPath embedded-file)
                 :policy (.getPath policy-file)
                 :output (.getPath output)
                 :require-ready true})]
    (is (false? (:ok report)))
    (is (= :component-not-ready (get-in report [:failures 0 :kind])))
    (is (= "ZIL-RETIREMENT/1"
           (:schema (edn/read-string (slurp output)))))))

(deftest missing-policy-is-rejected-test
  (let [root (temp-dir)
        gate-file (write! root "gate.edn" (str (pr-str ready-gate) "\n"))
        verification-file (write! root "verification.edn" (str (pr-str verified) "\n"))
        embedded-file (write! root "embedded.edn" (str (pr-str embedded) "\n"))]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"policy does not exist"
         (retirement/run-guard!
          {:gate (.getPath gate-file)
           :verification (.getPath verification-file)
           :embedded (.getPath embedded-file)
           :policy (.getPath (io/file root "missing.edn"))
           :output (.getPath (io/file root "retirement.edn"))})))))

(deftest public-wrapper-is-native-first-test
  (let [wrapper (slurp "bin/zil")
        legacy (slurp "bin/zil-legacy")]
    (is (.contains wrapper "lake exe zil --"))
    (is (.contains wrapper "--legacy"))
    (is (not (.contains wrapper "clojure -M -m zil.cli")))
    (is (.contains legacy "clojure -M -m zil.cli"))))
