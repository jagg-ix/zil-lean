import Zil.Crypto.Sha256
import Zil.Json.Ordered

/-!
# Control-plane events and receipts

A control event is one observation or decision, bound to the SHA-256 of the exact authoritative result it records. Events
form a hash chain per stream; a batch of appended events is acknowledged by a receipt. Identities and digests derive from
exact canonical bytes (`ZIL-CONTROL-EVENT/1`, `ZIL-CONTROL-RECEIPT/1`), the same bytes the earlier Clojure control plane
wrote, so a store written by either can be verified by the other.
-/

namespace Zil.Control.Event

open Zil.Json Zil.Crypto

def eventSchema : String := "ZIL-CONTROL-EVENT/1"
def receiptSchema : String := "ZIL-CONTROL-RECEIPT/1"

/-- Digest of the empty chain: the "previous event" of a stream's first event. -/
def emptyChainSha256 : String := Sha256.ofText ""

/-- The order the earlier runtime wrote an event's twelve fields in. Its map type switched from insertion order to hash
order at that size, so the order is not the declared one; it is fixed here so digests agree byte for byte. -/
private def eventFields : List String :=
  ["event_id", "stream", "request_id", "schema", "base_revision", "event_type", "context_bundle_id",
   "decision_sha256", "plugin_id", "payload_sha256", "payload", "actor"]

private def receiptFields : List String :=
  ["schema", "receipt_id", "stream", "base_revision", "final_revision", "event_count", "batch_sha256",
   "committed_at_epoch_ms"]

/-- `sha256:` followed by exactly 64 lowercase hex digits. -/
def validSha256 (value : String) : Bool :=
  value.startsWith "sha256:" && value.length == 71 &&
    (value.toList.drop 7).all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- The JSON of `value` restricted to `fields`, in that order. -/
def canonicalJson (fields : List String) (value : J) : String :=
  write (.obj (fields.toArray.map fun field => (field, (value.get? field).getD .null)))

/-- Input to `prepare`: every binding is optional except the stream, the type, the actor and the decision digest. -/
structure EventInput where
  eventId : Option String := none
  stream : String
  eventType : String
  actor : String
  requestId : Option String := none
  baseRevision : Option String := none
  contextBundleId : Option String := none
  decisionSha256 : String
  pluginId : Option String := none
  payload : J := .obj #[]

/-- No characters, or only whitespace. -/
def isBlank (text : String) : Bool := text.all Char.isWhitespace

/-- A binding that was not supplied, or is blank, is written `-`. -/
private def optionalBinding (value : Option String) : String :=
  let text := value.getD "-"
  if isBlank text then "-" else text

/-- The prepared event: a JSON object with the fields of `eventFields`, in order, identity derived from its bytes. -/
def prepare (input : EventInput) : Except String J := do
  let payload ← canonical input.payload
  let payloadSha := Sha256.ofText (write payload)
  let build (eventId : String) : J :=
    .obj #[("schema", .str eventSchema), ("event_id", .str eventId), ("stream", .str input.stream),
           ("event_type", .str input.eventType), ("actor", .str input.actor),
           ("request_id", .str (optionalBinding input.requestId)),
           ("base_revision", .str (optionalBinding input.baseRevision)),
           ("context_bundle_id", .str (optionalBinding input.contextBundleId)),
           ("decision_sha256", .str input.decisionSha256),
           ("plugin_id", .str (optionalBinding input.pluginId)),
           ("payload_sha256", .str payloadSha), ("payload", payload)]
  let derived := "event:" ++ (Sha256.ofText (canonicalJson eventFields (build ""))).drop 7
  let value := build (input.eventId.getD derived)
  if isBlank input.stream then throw "control event stream must be nonempty"
  if isBlank input.eventType then throw "control event type must be nonempty"
  if isBlank input.actor then throw "control event actor must be nonempty"
  if !validSha256 input.decisionSha256 then throw "control event decision_sha256 is invalid"
  return value

/-- Read a stored or prepared event object back into an input, to prepare it again. -/
def inputOfJson (event : J) : Except String EventInput := do
  let get (key : String) : Except String String :=
    match event.getStr? key with
    | some text => pure text
    | none => throw s!"control event is missing {key}"
  return { eventId := event.getStr? "event_id", stream := ← get "stream", eventType := ← get "event_type",
           actor := ← get "actor", requestId := event.getStr? "request_id",
           baseRevision := event.getStr? "base_revision", contextBundleId := event.getStr? "context_bundle_id",
           decisionSha256 := ← get "decision_sha256", pluginId := event.getStr? "plugin_id",
           payload := (event.get? "payload").getD (.obj #[]) }

/-- Canonical bytes of an event. -/
def eventJson (event : J) : Except String String := do
  let prepared ← prepare (← inputOfJson event)
  return canonicalJson eventFields prepared

/-- Digest of an event chained to the digest before it and bound to its revision. -/
def eventSha256 (event : J) (previousEventSha256 : String) (revision : Nat) : Except String String := do
  if !validSha256 previousEventSha256 then throw "previous event digest is invalid"
  return Sha256.ofText (previousEventSha256 ++ "\n" ++ toString revision ++ "\n" ++ (← eventJson event))

/-- Digest of a payload's canonical bytes. -/
def payloadSha256 (payload : J) : Except String String := do
  return Sha256.ofText (write (← canonical payload))

structure ReceiptInput where
  receiptId : Option String := none
  stream : String
  baseRevision : Nat
  finalRevision : Nat
  eventCount : Nat
  batchSha256 : String
  committedAtEpochMs : Nat

def prepareReceipt (input : ReceiptInput) : Except String J := do
  let build (receiptId : String) : J :=
    .obj #[("schema", .str receiptSchema), ("receipt_id", .str receiptId), ("stream", .str input.stream),
           ("base_revision", .int input.baseRevision), ("final_revision", .int input.finalRevision),
           ("event_count", .int input.eventCount), ("batch_sha256", .str input.batchSha256),
           ("committed_at_epoch_ms", .int input.committedAtEpochMs)]
  let derived := "receipt:" ++ (Sha256.ofText (canonicalJson receiptFields (build ""))).drop 7
  if isBlank input.stream then throw "control receipt stream must be nonempty"
  if !validSha256 input.batchSha256 then throw "control receipt batch_sha256 is invalid"
  return build (input.receiptId.getD derived)

def receiptJson (receipt : J) : String := canonicalJson receiptFields receipt

def receiptSha256 (receipt : J) : String := Sha256.ofText (receiptJson receipt)

end Zil.Control.Event
