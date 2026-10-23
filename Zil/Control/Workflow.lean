import Zil.Store.ControlEvent

/-!
# Workflow projection

A replay of a control stream into per-workflow observations: what was seen, in what order, with which authoritative
decision digests. The projection never infers that an action is authorized, verified, recovered or safe unless the exact
Lean result recorded in an event says so.
-/

namespace Zil.Control.Workflow

open Zil.Json Zil.Store.ControlEvent

def reducerId : String := "zil.control.workflow/v1"
def projectionSchema : String := "ZIL-WORKFLOW-PROJECTION/1"

def workflowEventTypes : List String :=
  ["context-generated", "action-token-issued", "checkpoint-created", "action-consumed", "postcondition-observed",
   "recovery-started", "recovery-completed", "semantic-decision", "external-evidence-recorded"]

private def eventType (stored : StoredEvent) : String := stored.event.getStr? "event_type" |>.getD ""

def isWorkflowEvent (stored : StoredEvent) : Bool := workflowEventTypes.contains (eventType stored)

/-- The workflow an event belongs to: its payload's `workflow_id`, `action_id` or `token_id`, else its request. -/
private def workflowId (stored : StoredEvent) : Option String :=
  let payload := stored.event.get? "payload" |>.getD (.obj #[])
  (payload.getStr? "workflow_id").orElse fun _ =>
    (payload.getStr? "action_id").orElse fun _ =>
      (payload.getStr? "token_id").orElse fun _ => stored.event.getStr? "request_id"

private def observation (stored : StoredEvent) : J :=
  let e := stored.event
  .obj #[("revision", .int stored.revision), ("event-id", .str (e.getStr? "event_id" |>.getD "")),
         ("event-type", .str (eventType stored)), ("actor", .str (e.getStr? "actor" |>.getD "")),
         ("request-id", .str (e.getStr? "request_id" |>.getD "")),
         ("decision-sha256", .str (e.getStr? "decision_sha256" |>.getD "")),
         ("payload", e.get? "payload" |>.getD (.obj #[]))]

private structure WorkflowState where
  observations : Array J := #[]
  lastEvent : J := .null
  actors : Array String := #[]
  deriving Inhabited

structure Projection where
  revision : Nat := 0
  eventCount : Nat := 0
  workflows : Array (String × J) := #[]

private def insertionSort (items : Array String) : Array String :=
  items.qsort fun a b => compareKeys a b == .lt

/-- Reduce stored events into the projection. -/
def reduceEvents (events : Array StoredEvent) : Projection := Id.run do
  let mut revision := 0
  let mut count := 0
  let mut states : Array (String × WorkflowState) := #[]
  for stored in events do
    if isWorkflowEvent stored then
      let id := (workflowId stored).getD "workflow:unbound"
      let observed := observation stored
      let actor := stored.event.getStr? "actor" |>.getD ""
      count := count + 1
      revision := stored.revision
      match states.findIdx? (·.1 == id) with
      | some index =>
          let (key, state) := states[index]!
          let actors := if state.actors.contains actor then state.actors else state.actors.push actor
          states := states.set! index
            (key, { observations := state.observations.push observed, lastEvent := observed, actors })
      | none =>
          states := states.push (id, { observations := #[observed], lastEvent := observed, actors := #[actor] })
  let sorted := states.qsort fun a b => compareKeys a.1 b.1 == .lt
  let workflows := sorted.map fun (id, state) =>
    (id, J.obj #[("observations", .arr state.observations), ("last-event", state.lastEvent),
                 ("actors", .arr ((insertionSort state.actors).map J.str))])
  return { revision, eventCount := count, workflows }

/-- The projection as the value a snapshot stores. -/
def Projection.toJson (projection : Projection) : J :=
  .obj #[("schema", .str projectionSchema), ("reducer", .str reducerId), ("revision", .int projection.revision),
         ("event-count", .int projection.eventCount), ("workflows", .obj projection.workflows)]

def Projection.summary (projection : Projection) : J :=
  .obj #[("schema", .str projectionSchema), ("revision", .int projection.revision),
         ("event-count", .int projection.eventCount), ("workflow-count", .int projection.workflows.size),
         ("workflows", .arr (projection.workflows.map fun (id, value) =>
           .obj #[("workflow-id", .str id),
                  ("observation-count", .int ((value.get? "observations" >>= J.asArr?).map (·.size) |>.getD 0)),
                  ("last-event-type", ((value.get? "last-event").bind (·.get? "event-type")).getD .null),
                  ("last-decision-sha256", ((value.get? "last-event").bind (·.get? "decision-sha256")).getD .null),
                  ("actors", (value.get? "actors").getD (.arr #[]))]))]

/-- A recorded observation must name its type and a workflow (or a request to stand in for one). -/
def validateWorkflowEvent (eventType : String) (requestId : Option String) (payload : J) : Except String Unit := do
  unless workflowEventTypes.contains eventType do
    throw s!"unsupported workflow observation type {eventType}"
  let named := (payload.getStr? "workflow_id").orElse fun _ => requestId
  match named with
  | some text => if text.all Char.isWhitespace then throw "workflow event requires workflow_id or request_id" else pure ()
  | none => throw "workflow event requires workflow_id or request_id"

end Zil.Control.Workflow
