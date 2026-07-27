(ns zil.store.sqlite
  "Transactional SQLite event/snapshot store with compare-and-swap publication."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io])
  (:import [java.nio.charset StandardCharsets]
           [java.security MessageDigest]
           [java.sql DriverManager]))

(def schema
  ["CREATE TABLE IF NOT EXISTS module_heads (module TEXT PRIMARY KEY, current_revision TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS batches (batch_id INTEGER PRIMARY KEY AUTOINCREMENT, revision TEXT UNIQUE NOT NULL, module TEXT NOT NULL, base_revision TEXT, delta_digest TEXT NOT NULL, payload_json TEXT NOT NULL, complete INTEGER NOT NULL CHECK (complete = 1))"
   "CREATE TABLE IF NOT EXISTS operations (batch_id INTEGER NOT NULL REFERENCES batches(batch_id), ordinal INTEGER NOT NULL, op TEXT NOT NULL, cause TEXT NOT NULL, declaration TEXT NOT NULL, object_name TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL, PRIMARY KEY (batch_id, ordinal))"
   "CREATE TABLE IF NOT EXISTS snapshots (revision TEXT PRIMARY KEY REFERENCES batches(revision), module TEXT NOT NULL, facts_json TEXT NOT NULL, valid INTEGER NOT NULL CHECK (valid = 1))"
   "CREATE TABLE IF NOT EXISTS authorizations (agent_id TEXT NOT NULL, scope TEXT NOT NULL, PRIMARY KEY(agent_id,scope))"
   "CREATE TABLE IF NOT EXISTS leases (lease_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, module TEXT NOT NULL, scope TEXT NOT NULL, base_revision TEXT NOT NULL, expires_at INTEGER NOT NULL, status TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS checkpoints (checkpoint_id TEXT PRIMARY KEY, module TEXT NOT NULL, revision TEXT NOT NULL, created_by TEXT NOT NULL, snapshot_digest TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS actions (action_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, module TEXT NOT NULL, base_revision TEXT NOT NULL, scope TEXT NOT NULL, lease_id TEXT NOT NULL, checkpoint_id TEXT NOT NULL, rollback_kind TEXT NOT NULL, rollback_ref TEXT NOT NULL, preconditions_pass INTEGER NOT NULL, status TEXT NOT NULL, postconditions_pass INTEGER)"
   "CREATE TABLE IF NOT EXISTS action_tokens (token_id TEXT PRIMARY KEY, task_id TEXT NOT NULL, agent_id TEXT NOT NULL, module TEXT NOT NULL, base_revision TEXT NOT NULL, scope TEXT NOT NULL, lease_id TEXT NOT NULL, context_bundle_id TEXT NOT NULL, action_type TEXT NOT NULL, action_target TEXT NOT NULL, expected_effects_json TEXT NOT NULL, rollback_kind TEXT NOT NULL, rollback_ref TEXT NOT NULL, issued_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, status TEXT NOT NULL)"
   "CREATE TABLE IF NOT EXISTS checkpoint_tokens (token_id TEXT UNIQUE NOT NULL REFERENCES action_tokens(token_id), checkpoint_id TEXT UNIQUE NOT NULL REFERENCES checkpoints(checkpoint_id))"
   "CREATE TABLE IF NOT EXISTS action_outputs (action_id TEXT NOT NULL REFERENCES actions(action_id), ordinal INTEGER NOT NULL, artifact TEXT NOT NULL, artifact_hash TEXT NOT NULL, PRIMARY KEY(action_id,ordinal))"])

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes text StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and % 0xff)) digest))))

(defn connect [path]
  (Class/forName "org.sqlite.JDBC")
  (let [file (io/file path)
        parent (.getParentFile file)]
    (when parent (.mkdirs parent))
    (DriverManager/getConnection (str "jdbc:sqlite:" (.getCanonicalPath file)))))

(defn initialize! [conn]
  (with-open [statement (.createStatement conn)]
    (.execute statement "PRAGMA foreign_keys = ON")
    (.execute statement "PRAGMA journal_mode = WAL")
    (doseq [sql schema] (.execute statement sql)))
  conn)

(defn- query-one [conn sql parameters]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (with-open [rows (.executeQuery statement)]
      (when (.next rows) (.getString rows 1)))))

(defn current-revision [conn module]
  (query-one conn "SELECT current_revision FROM module_heads WHERE module = ?" [module]))

(defn- fact-key [fact]
  [(get fact "object") (get fact "relation") (get fact "subject")])

(defn- decode-facts [text]
  (if text
    (into (sorted-map) (map (juxt fact-key identity) (json/read-str text)))
    (sorted-map)))

(defn- encode-facts [facts]
  (json/write-str (vec (vals facts)) :escape-slash false))

(defn- validate-delta! [delta]
  (when-not (= "zil.lean-delta.v0.1" (get delta "format"))
    (throw (ex-info "Unsupported delta format" {:code :validation})))
  (when-not (true? (get delta "complete"))
    (throw (ex-info "Incomplete delta cannot be published" {:code :validation})))
  (when-not (= (get delta "operation_count") (count (get delta "operations")))
    (throw (ex-info "Delta operation_count mismatch" {:code :validation})))
  (doseq [entry (get delta "operations")]
    (let [fact (get entry "fact")]
      (when (and (= "proved_claim" (get fact "relation"))
                 (not= "value:false" (get fact "subject")))
        (throw (ex-info "Delta attempts to promote an external claim to proved"
                        {:code :trust-boundary :fact fact})))))
  delta)

(defn- apply-operations [facts operations]
  (reduce (fn [state entry]
            (let [fact (get entry "fact") key (fact-key fact)]
              (case (get entry "op")
                "assert" (assoc state key fact)
                "retract" (dissoc state key)
                (throw (ex-info "Unknown delta operation" {:entry entry})))))
          facts operations))

(defn- execute! [conn sql parameters]
  (with-open [statement (.prepareStatement conn sql)]
    (doseq [[index value] (map-indexed vector parameters)]
      (.setObject statement (inc index) value))
    (.executeUpdate statement)))

(defn publish-delta! [db-path delta-path]
  (let [payload (slurp delta-path) delta (validate-delta! (json/read-str payload))
        module (get delta "module") revision (get delta "revision")
        base (get delta "base_revision")]
    (with-open [conn (initialize! (connect db-path))]
      (.setAutoCommit conn false)
      (try
        (let [current (current-revision conn module)]
          (when-not (= current base)
            (throw (ex-info "Expected-base revision conflict"
                            {:code :revision-conflict :expected base :current current})))
          (let [old-json (when current (query-one conn "SELECT facts_json FROM snapshots WHERE revision = ? AND valid = 1" [current]))
                facts (apply-operations (decode-facts old-json) (get delta "operations"))]
            (execute! conn "INSERT INTO batches(revision,module,base_revision,delta_digest,payload_json,complete) VALUES(?,?,?,?,?,1)"
                      [revision module base (str "sha256:" (sha256 payload)) payload])
            (let [batch-id (Long/parseLong (query-one conn "SELECT batch_id FROM batches WHERE revision = ?" [revision]))]
              (doseq [[ordinal entry] (map-indexed vector (get delta "operations"))]
                (let [fact (get entry "fact")]
                  (execute! conn "INSERT INTO operations(batch_id,ordinal,op,cause,declaration,object_name,relation,subject) VALUES(?,?,?,?,?,?,?,?)"
                            [batch-id ordinal (get entry "op") (get entry "cause")
                             (get entry "declaration") (get fact "object")
                             (get fact "relation") (get fact "subject")]))))
            (execute! conn "INSERT INTO snapshots(revision,module,facts_json,valid) VALUES(?,?,?,1)"
                      [revision module (encode-facts facts)])
            (execute! conn "INSERT INTO module_heads(module,current_revision) VALUES(?,?) ON CONFLICT(module) DO UPDATE SET current_revision=excluded.current_revision"
                      [module revision])
            (.commit conn)
            {:ok true :module module :base_revision base :revision revision
             :fact_count (count facts) :operation_count (count (get delta "operations"))}))
        (catch Exception error
          (.rollback conn)
          (throw error))))))

(defn verify-store [db-path module]
  (with-open [conn (initialize! (connect db-path))]
    (let [current (current-revision conn module)
          stored (decode-facts (when current (query-one conn "SELECT facts_json FROM snapshots WHERE revision = ?" [current])))
          replayed (with-open [statement (.prepareStatement conn "SELECT o.op,o.object_name,o.relation,o.subject FROM operations o JOIN batches b ON b.batch_id=o.batch_id WHERE b.module=? ORDER BY b.batch_id,o.ordinal")]
                     (.setString statement 1 module)
                     (with-open [rows (.executeQuery statement)]
                       (loop [facts (sorted-map)]
                         (if (.next rows)
                           (let [fact {"object" (.getString rows 2) "relation" (.getString rows 3) "subject" (.getString rows 4)}]
                             (recur (if (= "assert" (.getString rows 1))
                                      (assoc facts (fact-key fact) fact)
                                      (dissoc facts (fact-key fact)))))
                           facts))))]
      {:ok (= stored replayed) :module module :revision current
       :stored_fact_count (count stored) :replayed_fact_count (count replayed)})))
