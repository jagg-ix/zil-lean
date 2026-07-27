(ns zil.bridge.theorem-ci
  "One-shot theorem formal pipeline:
   theorem contracts -> bridge module -> lts/constraint checks -> TLA/Lean exports."
  (:require [clojure.java.io :as io]
            [zil.bridge.lean4 :as bl]
            [zil.bridge.query-ci :as bqci]
            [zil.bridge.theorem :as bth]
            [zil.bridge.tla :as bt]
            [zil.model-exchange :as mx]))

(defn- file-stem
  [path]
  (let [name (.getName (io/file path))
        idx (.lastIndexOf name ".")]
    (if (pos? idx)
      (subs name 0 idx)
      name)))

(defn- ensure-dir!
  [path]
  (let [dir (io/file path)]
    (.mkdirs dir)
    (.getAbsolutePath dir)))

(defn- assert-ok!
  [stage report]
  (when-not (:ok report)
    (throw (ex-info (str "Theorem CI stage failed: " (name stage))
                    {:stage stage
                     :report report})))
  report)

(defn run-theorem-ci
  "Run theorem-centric integrated formal pipeline.

  Options:
  - :out-dir         output directory for generated artifacts (default: /tmp)
  - :bridge-module   override theorem-bridge module name
  - :query-ci-profile optional DSL profile name for query-ci stage
  - :query-ci-lib-dir optional lib dir for preprocess fallback in query-ci stage
  - :tla-module      override exported TLA module name
  - :lean-namespace  override exported Lean namespace"
  ([path]
   (run-theorem-ci path {}))
  ([path {:keys [out-dir bridge-module query-ci-profile query-ci-lib-dir tla-module lean-namespace]}]
   (let [out-dir* (ensure-dir! (or out-dir "/tmp"))
         stem (file-stem path)
         bridge-zc (.getAbsolutePath (io/file out-dir* (str stem ".theorem-bridge.zc")))
         bridge-tla (.getAbsolutePath (io/file out-dir* (str stem ".theorem-bridge.tla")))
         bridge-lean (.getAbsolutePath (io/file out-dir* (str stem ".theorem-bridge.lean")))
         query-ci-report (bqci/run-query-ci-path
                          path
                          (cond-> {:include_rows false}
                            query-ci-profile (assoc :profile query-ci-profile)
                            query-ci-lib-dir (assoc :lib-dir query-ci-lib-dir)))
         bridge-report (bth/theorem-contracts->bridge
                        path
                        (cond-> {:output-path bridge-zc}
                          bridge-module (assoc :module-name bridge-module)))
         _ (assert-ok! :query-ci query-ci-report)
         lts-report (mx/check-bundle bridge-zc {:profile :lts})
         constraint-report (mx/check-bundle bridge-zc {:profile :constraint})
         _ (assert-ok! :lts-check lts-report)
         _ (assert-ok! :constraint-check constraint-report)
         tla-report (bt/export-lts->tla
                     bridge-zc
                     (cond-> {:output-path bridge-tla}
                       tla-module (assoc :module-name tla-module)))
         lean-report (bl/export-lts->lean4
                      bridge-zc
                      (cond-> {:output-path bridge-lean}
                        lean-namespace (assoc :namespace lean-namespace)))]
     {:ok true
      :path path
      :out_dir out-dir*
      :artifacts {:bridge_zc bridge-zc
                  :bridge_tla bridge-tla
                  :bridge_lean bridge-lean}
      :bridge (dissoc bridge-report :text)
      :checks {:query_ci query-ci-report
               :lts lts-report
               :constraint constraint-report}
      :exports {:tla (dissoc tla-report :text)
                :lean (dissoc lean-report :text)}})))
