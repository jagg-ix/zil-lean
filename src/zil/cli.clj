(ns zil.cli
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.pprint :as pp]
            [clojure.string :as str]
            [clojure.walk :as walk]
            [zil.bridge.lean4 :as bl]
            [zil.bridge.lean-events :as ble]
            [zil.bridge.lean-delta :as bld]
            [zil.bridge.snapshot :as bsnap]
            [zil.bridge.workflow-lean :as workflow]
            [zil.bridge.souffle :as bs]
            [zil.bridge.tla :as bt]
            [zil.bridge.theorem :as bth]
            [zil.bridge.theorem-ci :as btci]
            [zil.bridge.theorem-dsl-ci :as btdsl]
            [zil.bridge.proof-obligation :as bpo]
            [zil.bridge.vstack-ci :as bvci]
            [zil.core :as core]
            [zil.embedded :as embedded]
            [zil.formalization.target :as formalization]
            [zil.import.hcl :as ih]
            [zil.interop :as zi]
            [zil.model-exchange :as mx]
            [zil.preprocess :as zp]
            [zil.recovery.drift :as drift]
            [zil.safety.action :as safety]
            [zil.store.sqlite :as store]))

(defn- read-json-file [path]
  (json/read-str (slurp path)))

(defn- query-plan-report
  [model-path lib-dir]
  (try
    (assoc (core/query-plan-file model-path)
           :path model-path
           :preprocessed false)
    (catch clojure.lang.ExceptionInfo e
      (if (re-find #"Unknown macro invocation" (.getMessage e))
        (let [pp (zp/preprocess-model
                  model-path
                  (cond-> {}
                    lib-dir (assoc :lib-dir lib-dir)))]
          (assoc (core/query-plan-program (:text pp))
                 :path model-path
                 :preprocessed true
                 :preprocess (dissoc pp :text)))
        (throw e)))))

(defn- query-ci-report
  [model-path lib-dir profile]
  (let [opts (cond-> {}
               profile (assoc :profile profile))]
    (try
      (assoc (core/query-ci-file model-path opts)
             :path model-path
             :preprocessed false)
      (catch clojure.lang.ExceptionInfo e
        (if (re-find #"Unknown macro invocation" (.getMessage e))
          (let [pp (zp/preprocess-model
                    model-path
                    (cond-> {}
                      lib-dir (assoc :lib-dir lib-dir)))
                report (core/query-ci-program (:text pp) opts)]
            (assoc report
                   :path model-path
                   :preprocessed true
                   :preprocess (dissoc pp :text)))
          (throw e))))))

(defn -main
  [& args]
  (let [cmd (first args)
        cmd-args (vec (rest args))
        arg (nth cmd-args 0 nil)
        a3 (nth cmd-args 1 nil)
        a4 (nth cmd-args 2 nil)
        a5 (nth cmd-args 3 nil)
        a6 (nth cmd-args 4 nil)
        a7 (nth cmd-args 5 nil)
        a8 (nth cmd-args 6 nil)
        [profile strict-units-only?]
        (cond
          (= a3 "--allow-mixed") [nil false]
          (= a4 "--allow-mixed") [a3 false]
          :else [a3 true])
        opts (cond-> {}
               profile (assoc :profile profile)
               (and (= cmd "commit-check") (false? strict-units-only?))
               (assoc :strict-units-only? false))]
    (cond
      (or (nil? cmd) (= cmd "--help") (= cmd "-h"))
      (do
        (binding [*out* *err*]
          (println "Usage:")
          (println "  ./bin/zil <program.zc>")
          (println "  ./bin/zil bundle-check <file-or-dir> [auto|tm.det|lts|constraint]")
          (println "  ./bin/zil commit-check <file-or-dir> [auto|tm.det|lts|constraint] [--allow-mixed]")
          (println "  ./bin/zil query-plan <model.zc> [output.edn] [lib_dir]")
          (println "  ./bin/zil query-ci <model.zc> [output.edn] [lib_dir] [dsl_profile]")
          (println "  ./bin/zil export-tla <file-or-dir> [output.tla] [module_name]")
          (println "  ./bin/zil export-lean <file-or-dir> [output.lean] [namespace]")
          (println "  ./bin/zil export-snapshot <model.zc> <output.json> [output.lean] [namespace]")
          (println "  ./bin/zil import-lean-events <events.json> <output.zc> [module_name]")
          (println "  ./bin/zil diff-lean-events <previous.json|-> <current.json> <output.delta.json>")
          (println "  ./bin/zil publish-lean-delta <store.sqlite> <delta.json>")
          (println "  ./bin/zil verify-lean-store <store.sqlite> <module_name>")
          (println "  ./bin/zil analyze-lean-drift <store.sqlite> <module_name> <requested_revision> [max_depth] [max_nodes]")
          (println "  ./bin/zil lean-context-preflight <store.sqlite> <module_name> <requested_revision>")
          (println "  ./bin/zil grant-zil-scope <store.sqlite> <agent_id> <scope>")
          (println "  ./bin/zil acquire-zil-lease <store.sqlite> <request.json>")
          (println "  ./bin/zil create-zil-checkpoint <store.sqlite> <request.json>")
          (println "  ./bin/zil zil-action-preflight <store.sqlite> <request.json>")
          (println "  ./bin/zil record-zil-action <store.sqlite> <request.json>")
          (println "  ./bin/zil verify-zil-action <store.sqlite> <action_id> <true|false>")
          (println "  ./bin/zil export-workflow-lean <store.sqlite> <module> <output.lean> <namespace> <as_of_epoch>")
          (println "  ./bin/zil formalization-next <targets.zc>")
          (println "  ./bin/zil formalization-check <targets.zc> <target_id> <lean_project_root>")
          (println "  ./bin/zil theorem-bridge <file-or-dir> [output.zc] [module_name]")
          (println "  ./bin/zil theorem-ci <file-or-dir> [out_dir] [bridge_module] [tla_module] [lean_namespace]")
          (println "  ./bin/zil proof-obligation-check <file-or-dir> [tool]")
          (println "  ./bin/zil vstack-ci <file-or-dir> [out_dir] [bridge_module] [tla_module] [lean_namespace] [summary_json] [obligation_tool]")
          (println "  ./bin/zil theorem-dsl-ci <model.zc> [out_dir] [bridge_module] [tla_module] [lean_namespace] [summary_json]")
          (println "  ./bin/zil import-hcl <file-or-dir> [output.zc] [module_name]")
          (println "  ./bin/zil import-data <input-file> [output.zc] [module_name] [format] [record_prefix]")
          (println "  ./bin/zil export-data <model.zc> [format] [output-file] [facts|queries|query_name]")
          (println "  ./bin/zil souffle-emit <model.zc> [output.dl]")
          (println "  ./bin/zil souffle-run <model.zc> [query_name] [--bin souffle] [--j N]")
          (println "  ./bin/zil preprocess <model.zc> [output.zc] [lib_dir]")
          (println "  ./bin/zil embedded-scan <file-or-dir> [output.zc] [module_name] [lib_dir]")
          (println "  ./bin/zil embedded-snapshot <file-or-dir> <baseline.json> [lib_dir]")
          (println "  ./bin/zil embedded-drift-check <file-or-dir> <baseline.json> [lib_dir]")
          (println "")
          (println "  clojure -M -m zil.cli <program.zc>")
          (println "  clojure -M -m zil.cli bundle-check <file-or-dir> [auto|tm.det|lts|constraint]")
          (println "  clojure -M -m zil.cli commit-check <file-or-dir> [auto|tm.det|lts|constraint] [--allow-mixed]")
          (println "  clojure -M -m zil.cli query-plan <model.zc> [output.edn] [lib_dir]")
          (println "  clojure -M -m zil.cli query-ci <model.zc> [output.edn] [lib_dir] [dsl_profile]")
          (println "  clojure -M -m zil.cli export-tla <file-or-dir> [output.tla] [module_name]")
          (println "  clojure -M -m zil.cli export-lean <file-or-dir> [output.lean] [namespace]")
          (println "  clojure -M -m zil.cli export-snapshot <model.zc> <output.json> [output.lean] [namespace]")
          (println "  clojure -M -m zil.cli import-lean-events <events.json> <output.zc> [module_name]")
          (println "  clojure -M -m zil.cli diff-lean-events <previous.json|-> <current.json> <output.delta.json>")
          (println "  clojure -M -m zil.cli publish-lean-delta <store.sqlite> <delta.json>")
          (println "  clojure -M -m zil.cli verify-lean-store <store.sqlite> <module_name>")
          (println "  clojure -M -m zil.cli analyze-lean-drift <store.sqlite> <module_name> <requested_revision> [max_depth] [max_nodes]")
          (println "  clojure -M -m zil.cli lean-context-preflight <store.sqlite> <module_name> <requested_revision>")
          (println "  clojure -M -m zil.cli grant-zil-scope <store.sqlite> <agent_id> <scope>")
          (println "  clojure -M -m zil.cli acquire-zil-lease <store.sqlite> <request.json>")
          (println "  clojure -M -m zil.cli create-zil-checkpoint <store.sqlite> <request.json>")
          (println "  clojure -M -m zil.cli zil-action-preflight <store.sqlite> <request.json>")
          (println "  clojure -M -m zil.cli record-zil-action <store.sqlite> <request.json>")
          (println "  clojure -M -m zil.cli verify-zil-action <store.sqlite> <action_id> <true|false>")
          (println "  clojure -M -m zil.cli export-workflow-lean <store.sqlite> <module> <output.lean> <namespace> <as_of_epoch>")
          (println "  clojure -M -m zil.cli formalization-next <targets.zc>")
          (println "  clojure -M -m zil.cli formalization-check <targets.zc> <target_id> <lean_project_root>")
          (println "  clojure -M -m zil.cli theorem-bridge <file-or-dir> [output.zc] [module_name]")
          (println "  clojure -M -m zil.cli theorem-ci <file-or-dir> [out_dir] [bridge_module] [tla_module] [lean_namespace]")
          (println "  clojure -M -m zil.cli proof-obligation-check <file-or-dir> [tool]")
          (println "  clojure -M -m zil.cli vstack-ci <file-or-dir> [out_dir] [bridge_module] [tla_module] [lean_namespace] [summary_json] [obligation_tool]")
          (println "  clojure -M -m zil.cli theorem-dsl-ci <model.zc> [out_dir] [bridge_module] [tla_module] [lean_namespace] [summary_json]")
          (println "  clojure -M -m zil.cli import-hcl <file-or-dir> [output.zc] [module_name]")
          (println "  clojure -M -m zil.cli import-data <input-file> [output.zc] [module_name] [format] [record_prefix]")
          (println "  clojure -M -m zil.cli export-data <model.zc> [format] [output-file] [facts|queries|query_name]")
          (println "  clojure -M -m zil.cli souffle-emit <model.zc> [output.dl]")
          (println "  clojure -M -m zil.cli souffle-run <model.zc> [query_name] [--bin souffle] [--j N]")
          (println "  clojure -M -m zil.cli preprocess <model.zc> [output.zc] [lib_dir]")
          (println "  clojure -M -m zil.cli embedded-scan <file-or-dir> [output.zc] [module_name] [lib_dir]")
          (println "  clojure -M -m zil.cli embedded-snapshot <file-or-dir> <baseline.json> [lib_dir]")
          (println "  clojure -M -m zil.cli embedded-drift-check <file-or-dir> <baseline.json> [lib_dir]"))
        (System/exit 2))

      (= cmd "bundle-check")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for bundle-check"))
          (System/exit 2))
        (try
          (let [report (mx/check-bundle arg opts)]
            (pp/pprint report)
            (when-not (:ok report)
              (System/exit 1)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "commit-check")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for commit-check"))
          (System/exit 2))
        (try
          (let [report (mx/check-commit arg opts)]
            (pp/pprint report)
            (when-not (:ok report)
              (System/exit 1)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "query-plan")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for query-plan"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                lib-dir (when (and a4 (not= a4 "-")) a4)
                report (query-plan-report arg lib-dir)]
            (if output-path
              (do
                (spit output-path (with-out-str (pp/pprint report)))
                (pp/pprint {:ok true
                            :output_path output-path
                            :query_count (count (:queries report))
                            :planner_hint (:planner_hint report)}))
              (pp/pprint report)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "query-ci")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for query-ci"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                lib-dir (when (and a4 (not= a4 "-")) a4)
                profile (when (and a5 (not= a5 "-")) a5)
                report (query-ci-report arg lib-dir profile)]
            (if output-path
              (do
                (spit output-path (with-out-str (pp/pprint report)))
                (pp/pprint {:ok (:ok report)
                            :output_path output-path
                            :selected_queries (count (:selected_queries report))
                            :selected_profiles (:selected_dsl_profiles report)}))
              (pp/pprint report))
            (when-not (:ok report)
              (System/exit 1)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "formalization-next")
      (if arg
        (if-let [target (formalization/next-target arg)]
          (pp/pprint target)
          (do (pp/pprint {:target nil :reason :no-ready-target}) (System/exit 1)))
        (do (binding [*out* *err*] (println "Usage: formalization-next <targets.zc>"))
            (System/exit 2)))

      (= cmd "formalization-check")
      (if (and arg a3 a4)
        (let [report (formalization/check-target arg a3 a4)]
          (pp/pprint report)
          (when-not (:ok report) (System/exit 1)))
        (do (binding [*out* *err*] (println "Usage: formalization-check <targets.zc> <target_id> <lean_project_root>"))
            (System/exit 2)))

      (= cmd "export-workflow-lean")
      (if (and arg a3 a4 a5 a6)
        (pp/pprint (workflow/export-workflow! arg a3 a4 a5 (Long/parseLong a6)))
        (do (binding [*out* *err*] (println "Usage: export-workflow-lean <store.sqlite> <module> <output.lean> <namespace> <as_of_epoch>"))
            (System/exit 2)))

      (= cmd "grant-zil-scope")
      (if (and arg a3 a4)
        (pp/pprint (safety/grant-scope! arg a3 a4))
        (do (binding [*out* *err*] (println "Usage: grant-zil-scope <store.sqlite> <agent_id> <scope>"))
            (System/exit 2)))

      (= cmd "acquire-zil-lease")
      (if (and arg a3)
        (pp/pprint (safety/acquire-lease! arg (walk/keywordize-keys (read-json-file a3))))
        (do (binding [*out* *err*] (println "Usage: acquire-zil-lease <store.sqlite> <request.json>"))
            (System/exit 2)))

      (= cmd "create-zil-checkpoint")
      (if (and arg a3)
        (pp/pprint (safety/create-checkpoint! arg (walk/keywordize-keys (read-json-file a3))))
        (do (binding [*out* *err*] (println "Usage: create-zil-checkpoint <store.sqlite> <request.json>"))
            (System/exit 2)))

      (= cmd "zil-action-preflight")
      (if (and arg a3)
        (let [report (safety/action-preflight arg (read-json-file a3))]
          (pp/pprint report) (when-not (:allowed report) (System/exit 1)))
        (do (binding [*out* *err*] (println "Usage: zil-action-preflight <store.sqlite> <request.json>"))
            (System/exit 2)))

      (= cmd "record-zil-action")
      (if (and arg a3)
        (pp/pprint (safety/record-action! arg (read-json-file a3)))
        (do (binding [*out* *err*] (println "Usage: record-zil-action <store.sqlite> <request.json>"))
            (System/exit 2)))

      (= cmd "verify-zil-action")
      (if (and arg a3 a4 (#{"true" "false"} a4))
        (pp/pprint (safety/verify-postconditions! arg a3 (= "true" a4)))
        (do (binding [*out* *err*] (println "Usage: verify-zil-action <store.sqlite> <action_id> <true|false>"))
            (System/exit 2)))

      (= cmd "analyze-lean-drift")
      (do
        (when-not (and arg a3 a4)
          (binding [*out* *err*] (println "Usage: analyze-lean-drift <store.sqlite> <module_name> <requested_revision> [max_depth] [max_nodes]"))
          (System/exit 2))
        (try
          (pp/pprint (drift/analyze-drift arg a3 a4
                                          {:max-depth (if a5 (Long/parseLong a5) 8)
                                           :max-nodes (if a6 (Long/parseLong a6) 1000)}))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*] (println (.getMessage e)) (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "lean-context-preflight")
      (do
        (when-not (and arg a3 a4)
          (binding [*out* *err*] (println "Usage: lean-context-preflight <store.sqlite> <module_name> <requested_revision>"))
          (System/exit 2))
        (let [report (drift/mutation-preflight arg a3 a4)]
          (pp/pprint report)
          (when-not (:allowed report) (System/exit 1))))

      (= cmd "publish-lean-delta")
      (do
        (when-not (and arg a3)
          (binding [*out* *err*] (println "Usage: publish-lean-delta <store.sqlite> <delta.json>"))
          (System/exit 2))
        (try (pp/pprint (store/publish-delta! arg a3))
             (catch clojure.lang.ExceptionInfo e
               (binding [*out* *err*] (println (.getMessage e)) (pp/pprint (ex-data e)))
               (System/exit 2))))

      (= cmd "verify-lean-store")
      (do
        (when-not (and arg a3)
          (binding [*out* *err*] (println "Usage: verify-lean-store <store.sqlite> <module_name>"))
          (System/exit 2))
        (let [report (store/verify-store arg a3)]
          (pp/pprint report)
          (when-not (:ok report) (System/exit 1))))

      (= cmd "diff-lean-events")
      (do
        (when-not (and arg a3 a4)
          (binding [*out* *err*]
            (println "Usage: diff-lean-events <previous.json|-> <current.json> <output.delta.json>"))
          (System/exit 2))
        (try
          (pp/pprint (bld/write-delta! arg a3 a4))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "import-lean-events")
      (do
        (when-not (and arg a3)
          (binding [*out* *err*]
            (println "Usage: import-lean-events <events.json> <output.zc> [module_name]"))
          (System/exit 2))
        (try
          (pp/pprint (ble/import-events! arg a3 (or a4 "lean.events.imported")))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "export-snapshot")
      (do
        (when-not (and arg a3)
          (binding [*out* *err*]
            (println "Usage: export-snapshot <model.zc> <output.json> [output.lean] [namespace]"))
          (System/exit 2))
        (try
          (let [report (bsnap/export-snapshot!
                        arg
                        (cond-> {:json-output a3}
                          a4 (assoc :lean-output a4)
                          a5 (assoc :namespace a5)))]
            (pp/pprint (dissoc report :snapshot)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "export-tla")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for export-tla"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :module-name a4))
                report (bt/export-lts->tla arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "export-lean")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for export-lean"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :namespace a4))
                report (bl/export-lts->lean4 arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "theorem-bridge")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for theorem-bridge"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :module-name a4))
                report (bth/theorem-contracts->bridge arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "theorem-ci")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for theorem-ci"))
          (System/exit 2))
        (try
          (let [out-dir (when (and a3 (not= a3 "-")) a3)
                bridge-module (when (and a4 (not= a4 "-")) a4)
                tla-module (when (and a5 (not= a5 "-")) a5)
                lean-namespace (when (and a6 (not= a6 "-")) a6)
                opts (cond-> {}
                       out-dir (assoc :out-dir out-dir)
                       bridge-module (assoc :bridge-module bridge-module)
                       tla-module (assoc :tla-module tla-module)
                       lean-namespace (assoc :lean-namespace lean-namespace))
                report (btci/run-theorem-ci arg opts)]
            (pp/pprint report))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "proof-obligation-check")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for proof-obligation-check"))
          (System/exit 2))
        (try
          (let [tool (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       tool (assoc :tool tool))
                report (bpo/run-proof-obligation-check arg opts)]
            (pp/pprint report)
            (when-not (:ok report)
              (System/exit 1)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "vstack-ci")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for vstack-ci"))
          (System/exit 2))
        (try
          (let [out-dir (when (and a3 (not= a3 "-")) a3)
                bridge-module (when (and a4 (not= a4 "-")) a4)
                tla-module (when (and a5 (not= a5 "-")) a5)
                lean-namespace (when (and a6 (not= a6 "-")) a6)
                summary-json (when (and a7 (not= a7 "-")) a7)
                obligation-tool (when (and a8 (not= a8 "-")) a8)
                opts (cond-> {}
                       out-dir (assoc :out-dir out-dir)
                       bridge-module (assoc :bridge-module bridge-module)
                       tla-module (assoc :tla-module tla-module)
                       lean-namespace (assoc :lean-namespace lean-namespace)
                       summary-json (assoc :summary-json summary-json)
                       obligation-tool (assoc :obligation-tool obligation-tool))
                report (bvci/run-vstack-ci arg opts)]
            (pp/pprint report))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "theorem-dsl-ci")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for theorem-dsl-ci"))
          (System/exit 2))
        (try
          (let [out-dir (when (and a3 (not= a3 "-")) a3)
                bridge-module (when (and a4 (not= a4 "-")) a4)
                tla-module (when (and a5 (not= a5 "-")) a5)
                lean-namespace (when (and a6 (not= a6 "-")) a6)
                summary-json (when (and a7 (not= a7 "-")) a7)
                opts (cond-> {}
                       out-dir (assoc :out-dir out-dir)
                       bridge-module (assoc :bridge-module bridge-module)
                       tla-module (assoc :tla-module tla-module)
                       lean-namespace (assoc :lean-namespace lean-namespace)
                       summary-json (assoc :summary-json summary-json))
                report (btdsl/run-theorem-dsl-ci arg opts)]
            (pp/pprint report))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "import-hcl")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing path for import-hcl"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :module-name a4))
                report (ih/import-path->zil arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "import-data")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing input-file for import-data"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :module-name a4)
                       a5 (assoc :format a5)
                       a6 (assoc :record-prefix a6))
                report (zi/import-data->zil arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "export-data")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for export-data"))
          (System/exit 2))
        (try
          (let [output-path (when (and a4 (not= a4 "-")) a4)
                opts (cond-> {}
                       a3 (assoc :format a3)
                       output-path (assoc :output-path output-path)
                       a5 (assoc :source a5))
                report (zi/export-model-data arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "souffle-emit")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for souffle-emit"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                compiled    (core/compile-file arg {:skip-stratify? true})]
            (if output-path
              ;; Schema .dl + separate facts dir (fast path — no ground atoms in .dl)
              (let [facts-dir-path (str output-path ".facts")
                    _   (bs/write-facts-dir! (:facts compiled) facts-dir-path)
                    dl  (bs/emit-souffle-schema compiled)
                    _   (bs/create-empty-fact-files! dl facts-dir-path)]
                (spit output-path dl)
                (pp/pprint {:ok true
                            :dl_path output-path
                            :facts_dir facts-dir-path
                            :facts (count (:facts compiled))
                            :rules (count (:rules compiled))
                            :queries (count (:queries compiled))}))
              ;; stdout — emit standalone self-contained .dl (ground atoms included)
              (print (bs/emit-souffle-program compiled))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "souffle-run")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for souffle-run"))
          (System/exit 2))
        (try
          (let [remaining (rest cmd-args)
                flag-pairs (partition-all 2 (filter #(str/starts-with? % "--") remaining))
                flags (into {} (for [[k v] flag-pairs] [(str/replace k "--" "") v]))
                souffle-bin (get flags "bin" "souffle")
                parallel (Integer/parseInt (get flags "j" "1"))
                query-name (first (remove #(str/starts-with? % "--") remaining))
                souffle-opts {:souffle-bin souffle-bin :parallel parallel}
                compiled (core/compile-file arg {:skip-stratify? true})
                queries (if query-name
                          (filterv #(= (:name %) query-name) (:queries compiled))
                          (:queries compiled))
                result (bs/execute-with-souffle (assoc compiled :queries queries) souffle-opts)]
            (pp/pprint (dissoc result :dl :stdout)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "preprocess")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing model path for preprocess"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                opts (cond-> {}
                       output-path (assoc :output-path output-path)
                       a4 (assoc :lib-dir a4))
                report (zp/preprocess-model arg opts)]
            (if output-path
              (pp/pprint (dissoc report :text))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "embedded-scan")
      (do
        (when-not arg
          (binding [*out* *err*]
            (println "Missing file-or-dir for embedded-scan"))
          (System/exit 2))
        (try
          (let [output-path (when (and a3 (not= a3 "-")) a3)
                report (embedded/scan-path arg
                         (cond-> {}
                           output-path (assoc :output-path output-path)
                           a4 (assoc :module-name a4)
                           a5 (assoc :lib-dir a5)))]
            (if output-path
              (pp/pprint (dissoc report :text :reports))
              (print (:text report))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2))))

      (= cmd "embedded-snapshot")
      (if (and arg a3)
        (try
          (pp/pprint (embedded/snapshot-path! arg a3
                       (cond-> {} a4 (assoc :lib-dir a4))))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2)))
        (do
          (binding [*out* *err*]
            (println "Usage: embedded-snapshot <file-or-dir> <baseline.json> [lib_dir]"))
          (System/exit 2)))

      (= cmd "embedded-drift-check")
      (if (and arg a3)
        (try
          (let [report (embedded/drift-check arg a3
                         (cond-> {} a4 (assoc :lib-dir a4)))]
            (pp/pprint report)
            (when (:drift report) (System/exit 1)))
          (catch clojure.lang.ExceptionInfo e
            (binding [*out* *err*]
              (println (.getMessage e))
              (pp/pprint (ex-data e)))
            (System/exit 2)))
        (do
          (binding [*out* *err*]
            (println "Usage: embedded-drift-check <file-or-dir> <baseline.json> [lib_dir]"))
          (System/exit 2)))

      :else
      (pp/pprint (core/execute-file cmd)))))
