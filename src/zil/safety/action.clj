(ns zil.safety.action
  "Durable action authorization, leases, checkpoints, and postcondition audit."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.store.sqlite :as store])
  (:import [java.nio.charset StandardCharsets]
           [java.security MessageDigest]))

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes text StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and % 0xff)) digest))))

(defn- execute! [conn sql parameters]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (.executeUpdate statement)))

(defn- query-row [conn sql parameters columns]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (with-open [rows (.executeQuery statement)]
      (when (.next rows)
        (into {} (map-indexed (fn [index column]
                               [column (.getObject rows (inc index))]) columns))))))

(defn grant-scope! [db-path agent-id scope]
  (with-open [conn (store/initialize! (store/connect db-path))]
    (execute! conn "INSERT OR IGNORE INTO authorizations(agent_id,scope) VALUES(?,?)"
              [agent-id scope])
    {:ok true :agent_id agent-id :scope scope}))

(defn acquire-lease! [db-path {:keys [lease-id agent-id module scope base-revision now ttl-seconds]}]
  (with-open [conn (store/initialize! (store/connect db-path))]
    (let [current (store/current-revision conn module)
          authorized (query-row conn "SELECT agent_id FROM authorizations WHERE agent_id=? AND scope=?"
                                [agent-id scope] [:agent])
          conflict (query-row conn "SELECT lease_id FROM leases WHERE module=? AND scope=? AND status='active' AND expires_at>?"
                              [module scope now] [:lease])]
      (when-not (= current base-revision)
        (throw (ex-info "Cannot lease stale context" {:code :context-stale :current current})))
      (when-not authorized
        (throw (ex-info "Agent is not authorized for requested scope" {:code :unauthorized-scope})))
      (when conflict
        (throw (ex-info "Scope already has an active lease" {:code :lease-conflict :lease (:lease conflict)})))
      (execute! conn "INSERT INTO leases(lease_id,agent_id,module,scope,base_revision,expires_at,status) VALUES(?,?,?,?,?,?,'active')"
                [lease-id agent-id module scope base-revision (+ now ttl-seconds)])
      {:ok true :lease_id lease-id :agent_id agent-id :module module :scope scope
       :base_revision base-revision :expires_at (+ now ttl-seconds)})))

(defn create-checkpoint! [db-path {:keys [checkpoint-id module revision agent-id]}]
  (with-open [conn (store/initialize! (store/connect db-path))]
    (when-not (= revision (store/current-revision conn module))
      (throw (ex-info "Checkpoint revision is stale" {:code :context-stale})))
    (let [snapshot (query-row conn "SELECT facts_json FROM snapshots WHERE revision=? AND module=? AND valid=1"
                              [revision module] [:facts])]
      (when-not snapshot
        (throw (ex-info "No valid snapshot for checkpoint" {:code :context-incomplete})))
      (let [digest (str "sha256:" (sha256 (:facts snapshot)))]
        (execute! conn "INSERT INTO checkpoints(checkpoint_id,module,revision,created_by,snapshot_digest) VALUES(?,?,?,?,?)"
                  [checkpoint-id module revision agent-id digest])
        {:ok true :checkpoint_id checkpoint-id :module module :revision revision
         :snapshot_digest digest}))))

(defn action-preflight [db-path request]
  (let [{:strs [agent_id module base_revision scope lease_id checkpoint_id
                preconditions_pass rollback]} request
        integrity (store/verify-store db-path module)]
    (with-open [conn (store/initialize! (store/connect db-path))]
      (let [authorization (query-row conn "SELECT agent_id FROM authorizations WHERE agent_id=? AND scope=?"
                                     [agent_id scope] [:agent])
            lease (query-row conn "SELECT agent_id,module,scope,base_revision,expires_at,status FROM leases WHERE lease_id=?"
                             [lease_id] [:agent :module :scope :revision :expires :status])
            checkpoint (query-row conn "SELECT module,revision FROM checkpoints WHERE checkpoint_id=?"
                                  [checkpoint_id] [:module :revision])
            now (long (get request "now" 0))
            failures (cond-> []
                       (not (:ok integrity)) (conj :store-replay-mismatch)
                       (not= base_revision (:revision integrity)) (conj :context-stale)
                       (nil? authorization) (conj :unauthorized-scope)
                       (nil? lease) (conj :missing-lease)
                       (and lease (or (not= agent_id (:agent lease))
                                      (not= module (:module lease))
                                      (not= scope (:scope lease))
                                      (not= base_revision (:revision lease))
                                      (not= "active" (:status lease))
                                      (<= (long (:expires lease)) now))) (conj :invalid-lease)
                       (or (nil? checkpoint)
                           (not= module (:module checkpoint))
                           (not= base_revision (:revision checkpoint))) (conj :missing-current-checkpoint)
                       (not (true? preconditions_pass)) (conj :precondition-failed)
                       (not (#{"rollback" "compensation"} (get rollback "kind"))) (conj :missing-rollback)
                       (str/blank? (str (get rollback "reference" ""))) (conj :missing-rollback))]
        {:allowed (empty? failures) :code (first failures) :failures failures
         :module module :agent_id agent_id :scope scope
         :base_revision base_revision :current_revision (:revision integrity)
         :store_integrity (:ok integrity)}))))

(defn record-action! [db-path request]
  (let [preflight (action-preflight db-path request)]
    (when-not (:allowed preflight)
      (throw (ex-info "Action preflight denied" (assoc preflight :code :preflight-failed))))
    (with-open [conn (store/initialize! (store/connect db-path))]
      (.setAutoCommit conn false)
      (try
        ;; Recheck the compare-and-swap boundary inside the recording transaction.
        (when-not (= (get request "base_revision")
                     (store/current-revision conn (get request "module")))
          (throw (ex-info "Context changed after preflight" {:code :context-stale})))
        (let [rollback (get request "rollback")]
          (execute! conn "INSERT INTO actions(action_id,agent_id,module,base_revision,scope,lease_id,checkpoint_id,rollback_kind,rollback_ref,preconditions_pass,status) VALUES(?,?,?,?,?,?,?,?,?,1,'recorded')"
                    (conj (mapv #(get request %) ["action_id" "agent_id" "module" "base_revision"
                                                  "scope" "lease_id" "checkpoint_id"])
                          (get rollback "kind") (get rollback "reference")))
          (.commit conn)
          {:ok true :status :recorded :action_id (get request "action_id")
           :base_revision (get request "base_revision")})
        (catch Exception error
          (.rollback conn)
          (throw error))))))

(defn verify-postconditions! [db-path action-id passed]
  (with-open [conn (store/initialize! (store/connect db-path))]
    (let [updated (execute! conn "UPDATE actions SET postconditions_pass=?, status=? WHERE action_id=? AND status='recorded'"
                            [(if passed 1 0) (if passed "verified" "recovery_required") action-id])]
      (when-not (= 1 updated)
        (throw (ex-info "Action is missing or not awaiting verification" {:code :invalid-action-state})))
      {:ok passed :action_id action-id
       :status (if passed :verified :recovery-required)
       :code (when-not passed :postcondition-failed)})))

(def ^:private preflight-evidence-keys
  ["context_fresh" "context_complete" "no_critical_conflict"
   "authorized" "valid_lease" "preconditions_pass" "recovery_available"])

(defn issue-action-token!
  "Issue a short-lived preflight token before checkpoint creation.

  The caller supplies resolved context evidence, but authorization, lease,
  revision, expiry, and replay integrity are rechecked against durable state.
  No token is persisted when any prerequisite fails."
  [db-path request]
  (let [{:strs [token_id task_id agent_id module base_revision scope lease_id
                context_bundle_id action rollback evidence now ttl_seconds]} request
        integrity (store/verify-store db-path module)]
    (with-open [conn (store/initialize! (store/connect db-path))]
      (let [authorization (query-row conn "SELECT agent_id FROM authorizations WHERE agent_id=? AND scope=?"
                                     [agent_id scope] [:agent])
            lease (query-row conn "SELECT agent_id,module,scope,base_revision,expires_at,status FROM leases WHERE lease_id=?"
                             [lease_id] [:agent :module :scope :revision :expires :status])
            evidence-failures (for [key preflight-evidence-keys
                                    :when (not (true? (get evidence key)))]
                                (keyword (str/replace key "_" "-")))
            failures (cond-> (vec evidence-failures)
                       (not (:ok integrity)) (conj :store-replay-mismatch)
                       (not= base_revision (:revision integrity)) (conj :context-stale)
                       (nil? authorization) (conj :unauthorized-scope)
                       (nil? lease) (conj :missing-lease)
                       (and lease (or (not= agent_id (:agent lease))
                                      (not= module (:module lease))
                                      (not= scope (:scope lease))
                                      (not= base_revision (:revision lease))
                                      (not= "active" (:status lease))
                                      (<= (long (:expires lease)) (long now)))) (conj :invalid-lease)
                       (not (#{"rollback" "compensation"} (get rollback "kind"))) (conj :missing-rollback)
                       (str/blank? (str (get rollback "reference" ""))) (conj :missing-rollback)
                       (or (nil? ttl_seconds) (not (pos? (long (or ttl_seconds 0))))) (conj :invalid-token-ttl)
                       (str/blank? (str (get action "type" ""))) (conj :invalid-action)
                       (str/blank? (str (get action "target" ""))) (conj :invalid-action))]
        (if (seq failures)
          {:allowed false :failures failures :required_checkpoint true
           :base_revision base_revision :current_revision (:revision integrity)}
          (let [expires-at (min (+ (long now) (long ttl_seconds))
                                (long (:expires lease)))]
            (execute! conn "INSERT INTO action_tokens(token_id,task_id,agent_id,module,base_revision,scope,lease_id,context_bundle_id,action_type,action_target,expected_effects_json,rollback_kind,rollback_ref,issued_at,expires_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'issued')"
                      [token_id task_id agent_id module base_revision scope lease_id
                       context_bundle_id (get action "type") (get action "target")
                       (json/write-str (vec (get action "expected_effects" [])))
                       (get rollback "kind") (get rollback "reference") now expires-at])
            {:allowed true :action_token token_id :required_checkpoint true
             :expires_at_epoch expires-at :expires_at_revision base_revision
             :required_postconditions (vec (get action "required_postconditions" []))
             :evidence (assoc evidence "checkpoint_exists" false)}))))))

(defn create-token-checkpoint!
  "Create a checkpoint bound to an issued action token at the same revision."
  [db-path {:strs [checkpoint_id action_token agent_id now]}]
  (with-open [conn (store/initialize! (store/connect db-path))]
    (.setAutoCommit conn false)
    (try
      (let [token (query-row conn "SELECT agent_id,module,base_revision,expires_at,status FROM action_tokens WHERE token_id=?"
                             [action_token] [:agent :module :revision :expires :status])]
        (when-not token
          (throw (ex-info "Unknown action token" {:code :invalid-action-token})))
        (when-not (and (= "issued" (:status token))
                       (= agent_id (:agent token))
                       (< (long now) (long (:expires token))))
          (throw (ex-info "Action token is expired, consumed, or belongs to another agent"
                          {:code :invalid-action-token})))
        (when-not (= (:revision token) (store/current-revision conn (:module token)))
          (throw (ex-info "Action token revision is stale" {:code :context-stale})))
        (let [snapshot (query-row conn "SELECT facts_json FROM snapshots WHERE revision=? AND module=? AND valid=1"
                                  [(:revision token) (:module token)] [:facts])]
          (when-not snapshot
            (throw (ex-info "No valid snapshot for token checkpoint" {:code :context-incomplete})))
          (let [digest (str "sha256:" (sha256 (:facts snapshot)))]
            (execute! conn "INSERT INTO checkpoints(checkpoint_id,module,revision,created_by,snapshot_digest) VALUES(?,?,?,?,?)"
                      [checkpoint_id (:module token) (:revision token) agent_id digest])
            (execute! conn "INSERT INTO checkpoint_tokens(token_id,checkpoint_id) VALUES(?,?)"
                      [action_token checkpoint_id])
            (execute! conn "UPDATE action_tokens SET status='checkpointed' WHERE token_id=? AND status='issued'"
                      [action_token])
            (.commit conn)
            {:ok true :checkpoint_id checkpoint_id :action_token action_token
             :revision (:revision token) :snapshot_digest digest})))
      (catch Exception error
        (.rollback conn)
        (throw error)))))

(defn record-token-action!
  "Record execution only when checkpoint and token bindings still match."
  [db-path {:strs [action_id action_token checkpoint_id now observed_outputs]}]
  (when-not (every? (fn [output]
                      (and (not (str/blank? (str (get output "artifact" ""))))
                           (re-matches #"sha256:[0-9a-f]{64}" (str (get output "hash" "")))))
                    observed_outputs)
    (throw (ex-info "Observed outputs require artifact identifiers and SHA-256 hashes"
                    {:code :invalid-observed-output})))
  (let [integrity-module
        (with-open [conn (store/initialize! (store/connect db-path))]
          (:module (query-row conn "SELECT module FROM action_tokens WHERE token_id=?"
                              [action_token] [:module])))
        integrity (when integrity-module (store/verify-store db-path integrity-module))]
    (with-open [conn (store/initialize! (store/connect db-path))]
      (.setAutoCommit conn false)
      (try
        (let [token (query-row conn "SELECT agent_id,module,base_revision,scope,lease_id,rollback_kind,rollback_ref,expires_at,status FROM action_tokens WHERE token_id=?"
                               [action_token] [:agent :module :revision :scope :lease :rollback-kind :rollback-ref :expires :status])
              binding (query-row conn "SELECT checkpoint_id FROM checkpoint_tokens WHERE token_id=?"
                                 [action_token] [:checkpoint])
              checkpoint (when token
                           (query-row conn "SELECT module,revision FROM checkpoints WHERE checkpoint_id=?"
                                      [checkpoint_id] [:module :revision]))
              lease (when token
                      (query-row conn "SELECT agent_id,module,scope,base_revision,expires_at,status FROM leases WHERE lease_id=?"
                                 [(:lease token)] [:agent :module :scope :revision :expires :status]))]
          (when-not (and token integrity (:ok integrity)
                         (= (:revision token) (:revision integrity))
                         (= (:revision token) (store/current-revision conn (:module token)))
                         (= "checkpointed" (:status token))
                         (= checkpoint_id (:checkpoint binding))
                         (= (:module token) (:module checkpoint))
                         (= (:revision token) (:revision checkpoint))
                         (< (long now) (long (:expires token)))
                         (= (:agent token) (:agent lease))
                         (= (:module token) (:module lease))
                         (= (:scope token) (:scope lease))
                         (= (:revision token) (:revision lease))
                         (= "active" (:status lease))
                         (< (long now) (long (:expires lease))))
            (throw (ex-info "Action token lacks current safety evidence and a matching checkpoint"
                            {:code :missing-current-checkpoint})))
          (execute! conn "INSERT INTO actions(action_id,agent_id,module,base_revision,scope,lease_id,checkpoint_id,rollback_kind,rollback_ref,preconditions_pass,status) VALUES(?,?,?,?,?,?,?,?,?,1,'recorded')"
                    [action_id (:agent token) (:module token) (:revision token) (:scope token)
                     (:lease token) checkpoint_id (:rollback-kind token) (:rollback-ref token)])
          (doseq [[ordinal output] (map-indexed vector observed_outputs)]
            (execute! conn "INSERT INTO action_outputs(action_id,ordinal,artifact,artifact_hash) VALUES(?,?,?,?)"
                      [action_id ordinal (get output "artifact") (get output "hash")]))
          (when-not (= 1 (execute! conn "UPDATE action_tokens SET status='consumed' WHERE token_id=? AND status='checkpointed'"
                                   [action_token]))
            (throw (ex-info "Action token was concurrently consumed" {:code :invalid-action-token})))
          (.commit conn)
          {:ok true :status :recorded :action_id action_id
           :base_revision (:revision token) :action_token action_token
           :observed_output_count (count observed_outputs)})
        (catch Exception error
          (.rollback conn)
          (throw error))))))
