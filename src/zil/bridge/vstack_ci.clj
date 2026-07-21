(ns zil.bridge.vstack-ci
  "One-shot V-Stack formal pipeline:
   theorem contracts + refinement relations -> sidecar modules -> lts/constraint checks -> TLA/Lean exports."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [zil.bridge.formal-feedback :as bff]
            [zil.bridge.lean4 :as bl]
            [zil.bridge.proof-obligation :as bpo]
            [zil.bridge.query-ci :as bqci]
            [zil.bridge.theorem :as bth]
            [zil.bridge.tla :as bt]
            [zil.bridge.vstack :as bv]
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

(defn- json-safe
  [x]
  (cond
    (map? x)
    (into {}
          (map (fn [[k v]]
                 [(if (keyword? k) (name k) (str k))
                  (json-safe v)]))
          x)
    (vector? x) (mapv json-safe x)
    (set? x) (mapv json-safe (sort (map pr-str x)))
    (seq? x) (mapv json-safe x)
    (keyword? x) (name x)
    (symbol? x) (name x)
    :else x))

(defn- write-json!
  [path payload]
  (let [out-file (io/file path)
        parent (.getParentFile out-file)]
    (when parent
      (.mkdirs parent))
    (spit out-file (json/write-str (json-safe payload))))
  path)

(defn- assert-ok!
  [stage report]
  (when-not (:ok report)
    (throw (ex-info (str "VStack CI stage failed: " (name stage))
                    {:stage stage
                     :report report})))
  report)

(defn- optional-stage
  [kind f]
  (try
    {:ok true
     :kind kind
     :status :generated
     :report (f)}
    (catch clojure.lang.ExceptionInfo e
      (let [msg (.getMessage e)
            skip? (or (and (= kind :theorem)
                           (re-find #"No theorem contracts found" msg))
                      (and (= kind :refinement)
                           (re-find #"No refinement relation declarations found" msg)))]
        (if skip?
          {:ok true
           :kind kind
           :status :skipped
           :reason msg}
          (throw e))))))

(defn run-vstack-ci
  "Run integrated V-Stack pipeline over theorem + refinement relation declarations.

  Options:
  - :out-dir         output directory for generated artifacts (default: /tmp)
  - :bridge-module   base module name; when present, stage suffixes are appended
                     (`.theorem`, `.refinement`)
  - :query-ci-profile optional DSL profile name for query-ci stage
  - :query-ci-lib-dir optional lib dir for preprocess fallback in query-ci stage
  - :obligation-tool tool filter for proof-obligation stage (default: z3)
  - :feedback-zc     output path for formal feedback sidecar .zc
                     (default: <out-dir>/<stem>.vstack.feedback.zc)
  - :feedback-module module name override for formal feedback sidecar
                     (default: <stem>.vstack.feedback)
  - :summary-json    output path for machine-readable summary JSON
                     (default: <out-dir>/<stem>.vstack.summary.json)
  - :tla-module      override exported TLA module name
  - :lean-namespace  override exported Lean namespace"
  ([path]
   (run-vstack-ci path {}))
  ([path {:keys [out-dir bridge-module query-ci-profile query-ci-lib-dir obligation-tool feedback-zc feedback-module summary-json tla-module lean-namespace]}]
   (let [out-dir* (ensure-dir! (or out-dir "/tmp"))
         stem (file-stem path)
         bundle-dir (ensure-dir! (.getAbsolutePath (io/file out-dir* (str stem ".vstack.bundle"))))
         theorem-zc (.getAbsolutePath (io/file bundle-dir (str stem ".theorem-bridge.zc")))
         refinement-zc (.getAbsolutePath (io/file bundle-dir (str stem ".refinement-bridge.zc")))
         bridge-tla (.getAbsolutePath (io/file out-dir* (str stem ".vstack.bridge.tla")))
         bridge-lean (.getAbsolutePath (io/file out-dir* (str stem ".vstack.bridge.lean")))
         feedback-zc* (or feedback-zc
                          (.getAbsolutePath (io/file out-dir* (str stem ".vstack.feedback.zc"))))
         summary-json* (or summary-json
                           (.getAbsolutePath (io/file out-dir* (str stem ".vstack.summary.json"))))
         theorem-module (when bridge-module (str bridge-module ".theorem"))
         refinement-module (when bridge-module (str bridge-module ".refinement"))
         theorem-stage (optional-stage
                        :theorem
                        #(bth/theorem-contracts->bridge
                          path
                          (cond-> {:output-path theorem-zc}
                            theorem-module (assoc :module-name theorem-module))))
         refinement-stage (optional-stage
                           :refinement
                           #(bv/refinement-contracts->bridge
                             path
                             (cond-> {:output-path refinement-zc}
                               refinement-module (assoc :module-name refinement-module))))
         generated-files (vec
                          (concat
                           (when (= :generated (:status theorem-stage)) [theorem-zc])
                           (when (= :generated (:status refinement-stage)) [refinement-zc])))]
     (when (empty? generated-files)
       (throw (ex-info "VStack CI found neither theorem contracts nor refinement relation declarations."
                       {:path path
                        :theorem theorem-stage
                        :refinement refinement-stage})))
     (let [po-report (bpo/run-proof-obligation-check
                      path
                      {:tool (or obligation-tool :z3)})
           query-ci-report (bqci/run-query-ci-path
                            path
                            (cond-> {:include_rows false}
                              query-ci-profile (assoc :profile query-ci-profile)
                              query-ci-lib-dir (assoc :lib-dir query-ci-lib-dir)))
           _ (assert-ok! :proof-obligation-check po-report)
           _ (assert-ok! :query-ci query-ci-report)
           lts-report (mx/check-bundle bundle-dir {:profile :lts})
           constraint-report (mx/check-bundle bundle-dir {:profile :constraint})
           _ (assert-ok! :lts-check lts-report)
           _ (assert-ok! :constraint-check constraint-report)
           tla-report (bt/export-lts->tla
                       bundle-dir
                       (cond-> {:output-path bridge-tla}
                         tla-module (assoc :module-name tla-module)))
           lean-report (bl/export-lts->lean4
                        bundle-dir
                        (cond-> {:output-path bridge-lean}
                          lean-namespace (assoc :namespace lean-namespace)))
           formal-feedback-report (bff/export-proof-obligations->formal-feedback
                                   po-report
                                   {:output-path feedback-zc*
                                    :module-name feedback-module
                                    :summary-json-path summary-json*})]
       (let [report {:ok true
                     :path path
                     :out_dir out-dir*
                     :artifacts {:bundle_dir bundle-dir
                                 :theorem_bridge_zc (when (= :generated (:status theorem-stage)) theorem-zc)
                                 :refinement_bridge_zc (when (= :generated (:status refinement-stage)) refinement-zc)
                                 :bridge_tla bridge-tla
                                 :bridge_lean bridge-lean
                                 :formal_feedback_zc feedback-zc*
                                 :summary_json summary-json*}
                     :stages {:theorem (if (:report theorem-stage)
                                         (dissoc (:report theorem-stage) :text)
                                         (dissoc theorem-stage :ok :kind))
                              :refinement (if (:report refinement-stage)
                                            (dissoc (:report refinement-stage) :text)
                                            (dissoc refinement-stage :ok :kind))}
                     :proof_obligations (dissoc po-report :obligations)
                     :formal_feedback formal-feedback-report
                     :checks {:query_ci query-ci-report
                              :lts lts-report
                              :constraint constraint-report}
                     :exports {:tla (dissoc tla-report :text)
                               :lean (dissoc lean-report :text)}}]
         (write-json! summary-json* report)
         report)))))
