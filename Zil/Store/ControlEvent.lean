import Zil.Control.Event
import Zil.Store.Sqlite

/-!
# Hash-chained control-event streams

Events are appended to a named stream under an expected-revision compare-and-swap, in one immediate SQLite transaction,
and acknowledged by a receipt. Each event's digest covers the digest before it, so any edit to a stored event breaks the
chain that `verifyStore` replays. The table layout is the one the earlier Clojure store used, so an existing database
opens and verifies unchanged.
-/

namespace Zil.Store.ControlEvent

open Zil.Json Zil.Crypto Zil.Control Zil.Store

/-- The tables of the delta/snapshot store, created along with the control tables as the earlier store did. -/
def baseSchema : List String :=
  ["CREATE TABLE IF NOT EXISTS module_heads (module TEXT PRIMARY KEY, current_revision TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS batches (batch_id INTEGER PRIMARY KEY AUTOINCREMENT, revision TEXT UNIQUE NOT NULL, module TEXT NOT NULL, base_revision TEXT, delta_digest TEXT NOT NULL, payload_json TEXT NOT NULL, complete INTEGER NOT NULL CHECK (complete = 1))",
   "CREATE TABLE IF NOT EXISTS operations (batch_id INTEGER NOT NULL REFERENCES batches(batch_id), ordinal INTEGER NOT NULL, op TEXT NOT NULL, cause TEXT NOT NULL, declaration TEXT NOT NULL, object_name TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL, PRIMARY KEY (batch_id, ordinal))",
   "CREATE TABLE IF NOT EXISTS snapshots (revision TEXT PRIMARY KEY REFERENCES batches(revision), module TEXT NOT NULL, facts_json TEXT NOT NULL, valid INTEGER NOT NULL CHECK (valid = 1))",
   "CREATE TABLE IF NOT EXISTS authorizations (agent_id TEXT NOT NULL, scope TEXT NOT NULL, PRIMARY KEY(agent_id,scope))",
   "CREATE TABLE IF NOT EXISTS leases (lease_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, module TEXT NOT NULL, scope TEXT NOT NULL, base_revision TEXT NOT NULL, expires_at INTEGER NOT NULL, status TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS checkpoints (checkpoint_id TEXT PRIMARY KEY, module TEXT NOT NULL, revision TEXT NOT NULL, created_by TEXT NOT NULL, snapshot_digest TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS actions (action_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, module TEXT NOT NULL, base_revision TEXT NOT NULL, scope TEXT NOT NULL, lease_id TEXT NOT NULL, checkpoint_id TEXT NOT NULL, rollback_kind TEXT NOT NULL, rollback_ref TEXT NOT NULL, preconditions_pass INTEGER NOT NULL, status TEXT NOT NULL, postconditions_pass INTEGER)",
   "CREATE TABLE IF NOT EXISTS action_tokens (token_id TEXT PRIMARY KEY, task_id TEXT NOT NULL, agent_id TEXT NOT NULL, module TEXT NOT NULL, base_revision TEXT NOT NULL, scope TEXT NOT NULL, lease_id TEXT NOT NULL, context_bundle_id TEXT NOT NULL, action_type TEXT NOT NULL, action_target TEXT NOT NULL, expected_effects_json TEXT NOT NULL, rollback_kind TEXT NOT NULL, rollback_ref TEXT NOT NULL, issued_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, status TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS checkpoint_tokens (token_id TEXT UNIQUE NOT NULL REFERENCES action_tokens(token_id), checkpoint_id TEXT UNIQUE NOT NULL REFERENCES checkpoints(checkpoint_id))",
   "CREATE TABLE IF NOT EXISTS action_outputs (action_id TEXT NOT NULL REFERENCES actions(action_id), ordinal INTEGER NOT NULL, artifact TEXT NOT NULL, artifact_hash TEXT NOT NULL, PRIMARY KEY(action_id,ordinal))"]

def controlSchema : List String :=
  ["CREATE TABLE IF NOT EXISTS control_stream_heads (stream TEXT PRIMARY KEY, current_revision INTEGER NOT NULL, current_event_sha256 TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS control_batches (receipt_id TEXT PRIMARY KEY, stream TEXT NOT NULL, base_revision INTEGER NOT NULL, final_revision INTEGER NOT NULL, event_count INTEGER NOT NULL, batch_sha256 TEXT NOT NULL, committed_at_epoch_ms INTEGER NOT NULL, receipt_sha256 TEXT NOT NULL)",
   "CREATE TABLE IF NOT EXISTS control_events (stream TEXT NOT NULL, revision INTEGER NOT NULL, event_id TEXT UNIQUE NOT NULL, event_type TEXT NOT NULL, actor TEXT NOT NULL, request_id TEXT NOT NULL, base_revision TEXT NOT NULL, context_bundle_id TEXT NOT NULL, decision_sha256 TEXT NOT NULL, plugin_id TEXT NOT NULL, payload_json TEXT NOT NULL, payload_sha256 TEXT NOT NULL, previous_event_sha256 TEXT NOT NULL, event_sha256 TEXT NOT NULL, receipt_id TEXT NOT NULL REFERENCES control_batches(receipt_id), PRIMARY KEY(stream, revision))",
   "CREATE TABLE IF NOT EXISTS control_snapshots (stream TEXT NOT NULL, revision INTEGER NOT NULL, reducer_id TEXT NOT NULL, state_json TEXT NOT NULL, state_sha256 TEXT NOT NULL, event_sha256 TEXT NOT NULL, PRIMARY KEY(stream, revision, reducer_id))"]

/-- Errors a caller can tell apart. -/
inductive StoreError where
  | revisionConflict (stream : String) (expected current : Nat)
  | eventStoreError (message : String)
  | snapshotError (message : String)
  | snapshotConflict (message : String)

def StoreError.kind : StoreError → String
  | .revisionConflict .. => "revision-conflict"
  | .eventStoreError .. => "event-store-error"
  | .snapshotError .. => "snapshot-error"
  | .snapshotConflict .. => "snapshot-conflict"

def StoreError.message : StoreError → String
  | .revisionConflict stream expected current =>
      s!"control event expected revision conflict (stream {stream}, expected {expected}, current {current})"
  | .eventStoreError message | .snapshotError message | .snapshotConflict message => message

/-- The kind of a store error that was thrown, or none for any other error. -/
def errorKind? (error : IO.Error) : Option String :=
  match error with
  | .userError text =>
      match text.splitOn ": " with
      | kind :: _ :: _ =>
          if ["revision-conflict", "event-store-error", "snapshot-error", "snapshot-conflict"].contains kind then some kind else none
      | _ => none
  | _ => none

def fail (error : StoreError) : IO α := throw (IO.userError s!"{error.kind}: {error.message}")

/-- Open the database and make sure every table exists. -/
def connect (path : System.FilePath) : IO Sqlite.Session := do
  let session ← Sqlite.open_ path
  try
    Sqlite.prepare session
    for sql in baseSchema ++ controlSchema do
      Sqlite.exec session (sql ++ ";")
    return session
  catch error =>
    try Sqlite.close session catch _ => pure ()
    throw error

def withConnection (path : System.FilePath) (action : Sqlite.Session → IO α) : IO α := do
  let session ← connect path
  try
    let result ← action session
    Sqlite.close session
    return result
  catch error =>
    try Sqlite.close session catch _ => pure ()
    throw error

private def ofExcept (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error message => throw (IO.userError message)

private def intField (row : J) (key : String) : IO Nat :=
  match row.getInt? key with
  | some n => pure n.toNat
  | none => throw (IO.userError s!"sqlite3 row lacks the integer {key}")

private def strField (row : J) (key : String) : IO String :=
  match row.getStr? key with
  | some text => pure text
  | none => throw (IO.userError s!"sqlite3 row lacks the text {key}")

/-- Current revision and event digest of a stream, `(0, empty chain)` when nothing was appended. -/
def currentHead (session : Sqlite.Session) (stream : String) : IO (Nat × String) := do
  let rows ← Sqlite.query session
    s!"SELECT current_revision, current_event_sha256 FROM control_stream_heads WHERE stream = {Sqlite.text stream};"
  match rows[0]? with
  | some row => return (← intField row "current_revision", ← strField row "current_event_sha256")
  | none => return (0, Event.emptyChainSha256)

def currentRevision (session : Sqlite.Session) (stream : String) : IO Nat := do
  return (← currentHead session stream).1

/-- Wall-clock milliseconds since the epoch, from SQLite. -/
private def nowMs (session : Sqlite.Session) : IO Nat := do
  let rows ← Sqlite.query session "SELECT CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) AS ms;"
  match rows[0]? with
  | some row => intField row "ms"
  | none => throw (IO.userError "SQLite returned no time")

structure StoredEvent where
  revision : Nat
  event : J
  previousEventSha256 : String
  eventSha256 : String
  receiptId : String := ""

def StoredEvent.toJson (stored : StoredEvent) : J :=
  .obj #[("revision", .int stored.revision), ("previous-event-sha256", .str stored.previousEventSha256),
         ("event-sha256", .str stored.eventSha256), ("event", stored.event)]

structure AppendResult where
  receipt : J
  receiptSha256 : String
  events : Array StoredEvent

def AppendResult.toJson (result : AppendResult) : J :=
  .obj #[("ok", .bool true), ("receipt", result.receipt), ("receipt_sha256", .str result.receiptSha256),
         ("events", .arr (result.events.map StoredEvent.toJson))]

/-- Digest of a batch: its revisions and event digests, in order. -/
def batchSha256 (events : Array StoredEvent) : String :=
  Sha256.ofText <| write <| .arr <| events.map fun stored =>
    .obj #[("revision", .int stored.revision), ("event_sha256", .str stored.eventSha256)]

/-- Append a nonempty batch of prepared events to `stream`, provided the stream is at `expectedRevision`. -/
def appendEvents (dbPath : System.FilePath) (stream : String) (expectedRevision : Nat) (events : Array J) :
    IO AppendResult := do
  if events.isEmpty then fail (.eventStoreError "control event batch must be nonempty")
  withConnection dbPath fun session => Sqlite.transaction session do
    let (current, previous) ← currentHead session stream
    if current != expectedRevision then fail (.revisionConflict stream expectedRevision current)
    let mut stored : Array StoredEvent := #[]
    let mut revision := current + 1
    let mut previousSha := previous
    for raw in events do
      let prepared ← ofExcept (Event.prepare (← ofExcept (Event.inputOfJson raw)))
      if prepared.getStr? "stream" != some stream then
        fail (.eventStoreError s!"control event stream disagrees with append target {stream}")
      let sha ← ofExcept (Event.eventSha256 prepared previousSha revision)
      stored := stored.push { revision, event := prepared, previousEventSha256 := previousSha, eventSha256 := sha }
      previousSha := sha
      revision := revision + 1
    let batchSha := batchSha256 stored
    let committedAt ← nowMs session
    let finalRevision := current + stored.size
    let receipt ← ofExcept <| Event.prepareReceipt
      { stream, baseRevision := current, finalRevision, eventCount := stored.size, batchSha256 := batchSha,
        committedAtEpochMs := committedAt }
    let receiptSha := Event.receiptSha256 receipt
    let receiptId := receipt.getStr? "receipt_id" |>.getD ""
    Sqlite.exec session
      s!"INSERT INTO control_batches(receipt_id,stream,base_revision,final_revision,event_count,batch_sha256,committed_at_epoch_ms,receipt_sha256) VALUES({Sqlite.text receiptId},{Sqlite.text stream},{current},{finalRevision},{stored.size},{Sqlite.text batchSha},{committedAt},{Sqlite.text receiptSha});"
    for item in stored do
      let e := item.event
      let field (key : String) : String := Sqlite.text (e.getStr? key |>.getD "")
      let payload := write (e.get? "payload" |>.getD (.obj #[]))
      Sqlite.exec session
        s!"INSERT INTO control_events(stream,revision,event_id,event_type,actor,request_id,base_revision,context_bundle_id,decision_sha256,plugin_id,payload_json,payload_sha256,previous_event_sha256,event_sha256,receipt_id) VALUES({Sqlite.text stream},{item.revision},{field "event_id"},{field "event_type"},{field "actor"},{field "request_id"},{field "base_revision"},{field "context_bundle_id"},{field "decision_sha256"},{field "plugin_id"},{Sqlite.text payload},{field "payload_sha256"},{Sqlite.text item.previousEventSha256},{Sqlite.text item.eventSha256},{Sqlite.text receiptId});"
    Sqlite.exec session
      s!"INSERT INTO control_stream_heads(stream,current_revision,current_event_sha256) VALUES({Sqlite.text stream},{finalRevision},{Sqlite.text previousSha}) ON CONFLICT(stream) DO UPDATE SET current_revision=excluded.current_revision,current_event_sha256=excluded.current_event_sha256;"
    return { receipt, receiptSha256 := receiptSha, events := stored.map fun s => { s with receiptId } }

/-- Stored events of a stream between two revisions, oldest first. -/
def readEvents (dbPath : System.FilePath) (stream : String) (fromRevision : Nat := 1) (toRevision : Nat := 9223372036854775807) :
    IO (Array StoredEvent) :=
  withConnection dbPath fun session => do
    let rows ← Sqlite.query session
      s!"SELECT revision,event_id,event_type,actor,request_id,base_revision,context_bundle_id,decision_sha256,plugin_id,payload_json,payload_sha256,previous_event_sha256,event_sha256,receipt_id FROM control_events WHERE stream={Sqlite.text stream} AND revision>={fromRevision} AND revision<={toRevision} ORDER BY revision;"
    let mut out := #[]
    for row in rows do
      let payload ← ofExcept (parse (← strField row "payload_json"))
      let event : J := .obj #[
        ("schema", .str Event.eventSchema), ("event_id", .str (← strField row "event_id")), ("stream", .str stream),
        ("event_type", .str (← strField row "event_type")), ("actor", .str (← strField row "actor")),
        ("request_id", .str (← strField row "request_id")), ("base_revision", .str (← strField row "base_revision")),
        ("context_bundle_id", .str (← strField row "context_bundle_id")),
        ("decision_sha256", .str (← strField row "decision_sha256")), ("plugin_id", .str (← strField row "plugin_id")),
        ("payload_sha256", .str (← strField row "payload_sha256")), ("payload", payload)]
      out := out.push { revision := ← intField row "revision", event,
                        previousEventSha256 := ← strField row "previous_event_sha256",
                        eventSha256 := ← strField row "event_sha256", receiptId := ← strField row "receipt_id" }
    return out

structure BatchRow where
  receiptId : String
  baseRevision : Nat
  finalRevision : Nat
  eventCount : Nat
  batchSha256 : String
  committedAtEpochMs : Nat
  receiptSha256 : String

def readBatches (dbPath : System.FilePath) (stream : String) : IO (Array BatchRow) :=
  withConnection dbPath fun session => do
    let rows ← Sqlite.query session
      s!"SELECT receipt_id,base_revision,final_revision,event_count,batch_sha256,committed_at_epoch_ms,receipt_sha256 FROM control_batches WHERE stream={Sqlite.text stream} ORDER BY final_revision;"
    let mut out := #[]
    for row in rows do
      out := out.push { receiptId := ← strField row "receipt_id", baseRevision := ← intField row "base_revision",
                        finalRevision := ← intField row "final_revision", eventCount := ← intField row "event_count",
                        batchSha256 := ← strField row "batch_sha256",
                        committedAtEpochMs := ← intField row "committed_at_epoch_ms",
                        receiptSha256 := ← strField row "receipt_sha256" }
    return out

/-- Replay the chain: contiguous revisions from 1, each event's digest recomputed from its bytes and the digest before. -/
def verifyStream (dbPath : System.FilePath) (stream : String) : IO J := do
  let events ← readEvents dbPath stream
  let mut expectedRevision := 1
  let mut previousSha := Event.emptyChainSha256
  for stored in events do
    let payload := stored.event.get? "payload" |>.getD (.obj #[])
    let computedPayload ← ofExcept (Event.payloadSha256 payload)
    let storedPayload := stored.event.getStr? "payload_sha256" |>.getD ""
    let computedEvent ← ofExcept (Event.eventSha256 stored.event previousSha stored.revision)
    if expectedRevision == stored.revision && previousSha == stored.previousEventSha256 &&
        computedPayload == storedPayload && computedEvent == stored.eventSha256 then
      expectedRevision := expectedRevision + 1
      previousSha := stored.eventSha256
    else
      return .obj #[("ok", .bool false), ("stream", .str stream), ("revision", .int stored.revision),
        ("expected-revision", .int expectedRevision), ("expected-previous-sha256", .str previousSha),
        ("stored-previous-sha256", .str stored.previousEventSha256),
        ("computed-payload-sha256", .str computedPayload), ("stored-payload-sha256", .str storedPayload),
        ("computed-event-sha256", .str computedEvent), ("stored-event-sha256", .str stored.eventSha256)]
  withConnection dbPath fun session => do
    let (headRevision, headSha) ← currentHead session stream
    return .obj #[("ok", .bool (expectedRevision - 1 == headRevision && previousSha == headSha)),
      ("stream", .str stream), ("revision", .int headRevision), ("event-count", .int events.size),
      ("event-sha256", .str headSha)]

/-- Every receipt agrees with the events it acknowledges. -/
def verifyReceipts (dbPath : System.FilePath) (stream : String) : IO J := do
  let events ← readEvents dbPath stream
  let batches ← readBatches dbPath stream
  for batch in batches do
    let mine := events.filter (·.receiptId == batch.receiptId)
    let computedBatch := batchSha256 mine
    let prepared ← ofExcept <| Event.prepareReceipt
      { receiptId := some batch.receiptId, stream, baseRevision := batch.baseRevision,
        finalRevision := batch.finalRevision, eventCount := batch.eventCount, batchSha256 := batch.batchSha256,
        committedAtEpochMs := batch.committedAtEpochMs }
    let computedReceipt := Event.receiptSha256 prepared
    unless batch.eventCount == mine.size && batch.batchSha256 == computedBatch &&
        batch.receiptSha256 == computedReceipt do
      return .obj #[("ok", .bool false), ("stream", .str stream), ("receipt-id", .str batch.receiptId),
        ("stored-event-count", .int batch.eventCount), ("computed-event-count", .int mine.size),
        ("stored-batch-sha256", .str batch.batchSha256), ("computed-batch-sha256", .str computedBatch),
        ("stored-receipt-sha256", .str batch.receiptSha256), ("computed-receipt-sha256", .str computedReceipt)]
  return .obj #[("ok", .bool true), ("stream", .str stream), ("batch-count", .int batches.size)]

private def okOf (value : J) : Bool := value.get? "ok" == some (.bool true)

/-- The chain and the receipts together. -/
def verifyStore (dbPath : System.FilePath) (stream : String) : IO J := do
  let chain ← verifyStream dbPath stream
  let receipts ← verifyReceipts dbPath stream
  return .obj #[("ok", .bool (okOf chain && okOf receipts)), ("stream", .str stream), ("chain", chain),
                ("receipts", receipts)]

/-- Store an immutable, nonauthoritative snapshot of a reduction of the stream at `revision`. -/
def writeSnapshot (dbPath : System.FilePath) (stream : String) (revision : Nat) (reducerId : String) (state : J) :
    IO J :=
  withConnection dbPath fun session => do
    let (headRevision, _) ← currentHead session stream
    if revision > headRevision then
      fail (.snapshotError s!"snapshot revision exceeds stream head (stream {stream}, revision {revision}, head {headRevision})")
    let eventSha? ← Sqlite.scalar? session
      s!"SELECT event_sha256 FROM control_events WHERE stream={Sqlite.text stream} AND revision={revision};" "event_sha256"
    let stateJson := write (← ofExcept (canonical state))
    let stateSha := Sha256.ofText stateJson
    let existing ← Sqlite.query session
      s!"SELECT state_sha256,event_sha256 FROM control_snapshots WHERE stream={Sqlite.text stream} AND revision={revision} AND reducer_id={Sqlite.text reducerId};"
    let some eventSha := eventSha?
      | fail (.snapshotError s!"snapshot revision has no event (stream {stream}, revision {revision})")
    let result (existed : Bool) : J :=
      .obj #[("ok", .bool true), ("existing", .bool existed), ("stream", .str stream), ("revision", .int revision),
             ("reducer-id", .str reducerId), ("state-sha256", .str stateSha), ("event-sha256", .str eventSha)]
    match existing[0]? with
    | some row =>
        if row.getStr? "state_sha256" == some stateSha && row.getStr? "event_sha256" == some eventSha then
          return result true
        else
          fail (.snapshotConflict s!"snapshot is immutable and already exists with different bytes (stream {stream}, revision {revision}, reducer {reducerId})")
    | none =>
        Sqlite.exec session
          s!"INSERT INTO control_snapshots(stream,revision,reducer_id,state_json,state_sha256,event_sha256) VALUES({Sqlite.text stream},{revision},{Sqlite.text reducerId},{Sqlite.text stateJson},{Sqlite.text stateSha},{Sqlite.text eventSha});"
        return result false

/-- A stored snapshot, if any. -/
def readSnapshot (dbPath : System.FilePath) (stream : String) (revision : Nat) (reducerId : String) : IO (Option J) :=
  withConnection dbPath fun session => do
    let rows ← Sqlite.query session
      s!"SELECT state_json,state_sha256,event_sha256 FROM control_snapshots WHERE stream={Sqlite.text stream} AND revision={revision} AND reducer_id={Sqlite.text reducerId};"
    match rows[0]? with
    | none => return none
    | some row =>
        return some (.obj #[("stream", .str stream), ("revision", .int revision), ("reducer-id", .str reducerId),
          ("state", ← ofExcept (parse (← strField row "state_json"))), ("state-sha256", .str (← strField row "state_sha256")),
          ("event-sha256", .str (← strField row "event_sha256"))])

end Zil.Store.ControlEvent
