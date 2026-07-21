(ns zil.bridge.workflow-lean
  "Generate frozen Lean workflow evidence from the SQLite operational store."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.store.sqlite :as store])
  (:import [java.nio.file Files StandardCopyOption]))

(defn- q [value] (pr-str (str value)))
(defn- bool-token [value] (if value "true" "false"))

(defn- action-rows [conn module]
  (with-open [statement (.prepareStatement conn "SELECT a.action_id,a.agent_id,a.module,a.base_revision,a.scope,a.lease_id,a.checkpoint_id,a.rollback_kind,a.rollback_ref,a.preconditions_pass,l.agent_id,l.module,l.scope,l.base_revision,l.expires_at,l.status,c.module,c.revision,CASE WHEN z.agent_id IS NULL THEN 0 ELSE 1 END FROM actions a LEFT JOIN leases l ON l.lease_id=a.lease_id LEFT JOIN checkpoints c ON c.checkpoint_id=a.checkpoint_id LEFT JOIN authorizations z ON z.agent_id=a.agent_id AND z.scope=a.scope WHERE a.module=? ORDER BY a.action_id")]
    (.setString statement 1 module)
    (with-open [rows (.executeQuery statement)]
      (loop [out []]
        (if (.next rows)
          (recur (conj out {:action-id (.getString rows 1) :agent-id (.getString rows 2)
                            :module (.getString rows 3) :base (.getString rows 4)
                            :scope (.getString rows 5) :lease-id (.getString rows 6)
                            :checkpoint-id (.getString rows 7) :rollback-kind (.getString rows 8)
                            :rollback-ref (.getString rows 9) :preconditions (= 1 (.getInt rows 10))
                            :lease-agent (.getString rows 11) :lease-module (.getString rows 12)
                            :lease-scope (.getString rows 13) :lease-revision (.getString rows 14)
                            :lease-expires (.getLong rows 15) :lease-status (.getString rows 16)
                            :checkpoint-module (.getString rows 17) :checkpoint-revision (.getString rows 18)
                            :authorized (= 1 (.getInt rows 19))}))
          out)))))

(defn collect-snapshot [db-path module as-of]
  (let [integrity (store/verify-store db-path module)]
    (with-open [conn (store/initialize! (store/connect db-path))]
      (let [current (store/current-revision conn module)
            actions (mapv (fn [row]
                            (assoc row
                                   :current current
                                   :context-fresh (= (:base row) current)
                                   :context-complete (boolean current)
                                   :no-conflict (:ok integrity)
                                   :valid-lease (and (= (:agent-id row) (:lease-agent row))
                                                     (= (:module row) (:lease-module row))
                                                     (= (:scope row) (:lease-scope row))
                                                     (= (:base row) (:lease-revision row))
                                                     (= "active" (:lease-status row))
                                                     (> (:lease-expires row) as-of))
                                   :checkpoint (and (= (:module row) (:checkpoint-module row))
                                                    (= (:base row) (:checkpoint-revision row)))
                                   :recovery (and (#{"rollback" "compensation"} (:rollback-kind row))
                                                  (not (str/blank? (:rollback-ref row))))))
                          (action-rows conn module))]
        {:revision current :complete (:ok integrity) :as-of as-of :actions actions}))))

(defn- lean-action [row]
  (str "{ actionId := " (q (:action-id row))
       ", agentId := " (q (:agent-id row))
       ", moduleName := " (q (:module row))
       ", baseRevision := " (q (:base row))
       ", currentRevision := " (q (:current row))
       ", contextFresh := " (bool-token (:context-fresh row))
       ", contextComplete := " (bool-token (:context-complete row))
       ", noConflict := " (bool-token (:no-conflict row))
       ", authorized := " (bool-token (:authorized row))
       ", validLease := " (bool-token (:valid-lease row))
       ", checkpointExists := " (bool-token (:checkpoint row))
       ", preconditionsPass := " (bool-token (:preconditions row))
       ", recoveryAvailable := " (bool-token (:recovery row)) " }"))

(defn render-lean [snapshot namespace]
  (let [actions (:actions snapshot)]
    (str "-- Generated from a frozen SQLite workflow snapshot. Do not edit.\n"
         "module\n\npublic import Zil.Workflow\n\n@[expose] public section\n\nnamespace "
         namespace "\n\nopen Zil.Workflow\n\n"
         "def snapshot : Snapshot := {\n  revision := " (q (:revision snapshot))
         "\n  complete := " (bool-token (:complete snapshot)) "\n  actions := ["
         (str/join ",\n    " (map lean-action actions)) "]\n}\n\n"
         (str/join "\n" (keep-indexed
                          (fn [index action]
                            (when (every? true? [(:context-fresh action) (:context-complete action)
                                                (:no-conflict action) (:authorized action)
                                                (:valid-lease action) (:checkpoint action)
                                                (:preconditions action) (:recovery action)])
                              (str "example : MayExecute snapshot.actions[" index
                                   "]! := by native_decide"))) actions))
         (when (seq actions) "\n") "\nend " namespace "\n")))

(defn- atomic-spit! [path text]
  (let [target (.toPath (io/file path)) parent (.getParent target)]
    (when parent (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0)))
    (let [tmp (Files/createTempFile parent ".zil-workflow-" ".tmp"
                                    (make-array java.nio.file.attribute.FileAttribute 0))]
      (spit (.toFile tmp) text)
      (Files/move tmp target (into-array StandardCopyOption
                                         [StandardCopyOption/ATOMIC_MOVE StandardCopyOption/REPLACE_EXISTING])))))

(defn export-workflow! [db-path module output namespace as-of]
  (let [snapshot (collect-snapshot db-path module as-of)]
    (when-not (:revision snapshot)
      (throw (ex-info "Cannot export workflow without a current snapshot" {:code :context-incomplete})))
    (atomic-spit! output (render-lean snapshot namespace))
    {:ok true :module module :revision (:revision snapshot) :complete (:complete snapshot)
     :action_count (count (:actions snapshot)) :as_of as-of :output output :namespace namespace}))
