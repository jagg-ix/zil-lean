import Zil.Control.Runtime
import Zil.Control.Workflow

/-!
# Durable decisions

Run a Lean-authoritative operation and append its exact decision envelope to a control stream, or append an observation
already bound to an authoritative decision or evidence hash, or replay a stream into an immutable workflow snapshot.
-/

namespace Zil.Control.Durable

open Zil.Json Zil.Control Zil.Store.ControlEvent Zil.Worker Zil.Crypto

private def ofExcept (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error message => throw (IO.userError message)

/-- The semantic fields of a response: everything but the payload text, in the order the decision digest covers. -/
def semanticPayload (response : Response) : J :=
  .obj #[("schema", .str response.schema), ("request_id", .str response.requestId),
         ("protocol_version", .int response.protocolVersion), ("operation", .str response.operation),
         ("status", .str response.status), ("authority", .str response.authority),
         ("assurance", .str response.assurance), ("input_sha256", .str response.inputSha256),
         ("result_sha256", .str response.resultSha256), ("errors", .arr (response.errors.map .str)),
         ("warnings", .arr (response.warnings.map .str))]

structure InvokeArguments where
  stream : String
  expectedRevision : Nat
  actor : String
  operation : String
  inputPath : String
  arguments : Array String := #[]
  baseRevision : String := "-"
  contextBundleId : Option String := none
  pluginId : String := "-"
  workflowId : Option String := none
  requestId : Option String := none
  timeoutMs : Option Nat := none

/-- Invoke one Lean-authoritative command and append its exact decision envelope. -/
def invokeAndRecord (plane : Runtime.ControlPlane) (dbPath : System.FilePath) (args : InvokeArguments) : IO J := do
  let response ← Runtime.execute plane args.operation args.inputPath args.arguments
    { baseRevision := args.baseRevision, requestId := args.requestId, timeoutMs := args.timeoutMs }
  let decisionSha :=
    if response.resultSha256.isEmpty then Sha256.ofText (write (semanticPayload response)) else response.resultSha256
  let event ← ofExcept <| Event.prepare
    { stream := args.stream, eventType := "semantic-decision", actor := args.actor,
      requestId := some response.requestId, baseRevision := some args.baseRevision,
      contextBundleId := args.contextBundleId, decisionSha256 := decisionSha, pluginId := some args.pluginId,
      payload := .obj #[("workflow_id", .str (args.workflowId.getD response.requestId)),
                        ("response", semanticPayload response)] }
  let persisted ← appendEvents dbPath args.stream args.expectedRevision #[event]
  return .obj #[("ok", .bool (response.status == "ok")), ("response", response.toJson),
                ("event", (persisted.events[0]?.map StoredEvent.toJson).getD .null),
                ("receipt", persisted.receipt), ("receipt-sha256", .str persisted.receiptSha256)]

structure RecordArguments where
  stream : String
  expectedRevision : Nat
  eventType : String
  actor : String
  requestId : Option String := none
  baseRevision : Option String := none
  contextBundleId : Option String := none
  decisionSha256 : String
  pluginId : Option String := none
  payload : J

/-- Append an observation already bound to an authoritative decision or evidence hash. -/
def recordWorkflowEvent (dbPath : System.FilePath) (args : RecordArguments) : IO AppendResult := do
  ofExcept (Workflow.validateWorkflowEvent args.eventType args.requestId args.payload)
  let event ← ofExcept <| Event.prepare
    { stream := args.stream, eventType := args.eventType, actor := args.actor, requestId := args.requestId,
      baseRevision := args.baseRevision, contextBundleId := args.contextBundleId, decisionSha256 := args.decisionSha256,
      pluginId := args.pluginId, payload := args.payload }
  appendEvents dbPath args.stream args.expectedRevision #[event]

/-- Replay a stream into an immutable nonauthoritative workflow snapshot. -/
def projectWorkflows (dbPath : System.FilePath) (stream : String) : IO J := do
  let events ← readEvents dbPath stream
  let projection := Workflow.reduceEvents events
  if projection.revision == 0 then
    return .obj #[("ok", .bool true), ("stream", .str stream), ("revision", .int 0),
                  ("projection", projection.toJson), ("snapshot", .null)]
  let snapshot ← writeSnapshot dbPath stream projection.revision Workflow.reducerId projection.toJson
  return .obj #[("ok", .bool true), ("stream", .str stream), ("revision", .int projection.revision),
                ("projection", projection.toJson), ("snapshot", snapshot)]

/-- Integrity of the stream and a summary of its workflows. -/
def workflowStatus (dbPath : System.FilePath) (stream : String) : IO J := do
  let events ← readEvents dbPath stream
  let projection := Workflow.reduceEvents events
  return .obj #[("stream", .str stream), ("integrity", ← verifyStore dbPath stream), ("projection", projection.summary)]

end Zil.Control.Durable
