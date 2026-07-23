import Zil

open Zil

private def statusOpen : RelExpr :=
  .mkWithAttrs
    (.ground `task.release)
    `zil.status
    (.ground `value.current)
    #[{ key := `state, value := .text "open" }]

private def statusClosed : RelExpr :=
  .mkWithAttrs
    (.ground `task.release)
    `zil.status
    (.ground `value.current)
    #[{ key := `state, value := .text "closed" }]

private def store : RevisionStore := {
  moduleName := `project.release
  records := #[
    { fact := statusOpen, revision := 1, event := `event.e1, operation := .assert },
    { fact := statusOpen, revision := 2, event := `event.e2, operation := .retract },
    { fact := statusClosed, revision := 3, event := `event.e3, operation := .assert }
  ]
  causal := { edges := #[
    { left := `event.e1, right := `event.e2 },
    { left := `event.e2, right := `event.e3 }
  ] }
}

#guard store.valid
#guard store.latestRevision == 3
#guard store.causal.before `event.e1 `event.e3
#guard !store.causal.before `event.e3 `event.e1
#guard store.causal.concurrent `event.e1 `event.independent
#guard Zil.Codec.Revision.roundTrips store

#guard match store.snapshotAt 1 with
  | .ok facts => facts.size == 1 && facts[0]!.semanticallyEqual statusOpen
  | .error _ => false

#guard match store.snapshotAt 2 with
  | .ok facts => facts.isEmpty
  | .error _ => false

#guard match store.snapshotAt 3 with
  | .ok facts => facts.size == 1 && facts[0]!.semanticallyEqual statusClosed
  | .error _ => false

#guard match store.causal.addEdge { left := `event.e3, right := `event.e1 } with
  | .error _ => true
  | .ok _ => false

private def duplicateRevisionStore : RevisionStore := {
  store with
  records := store.records.push {
    fact := statusClosed
    revision := 3
    event := `event.duplicate
    operation := .retract
  }
}

#guard !duplicateRevisionStore.valid

private def vectorA : VectorClock := {
  entries := #[(`worker.a, 2), (`worker.b, 1)]
}

private def vectorB : VectorClock := {
  entries := #[(`worker.a, 3), (`worker.b, 1)]
}

private def vectorConcurrent : VectorClock := {
  entries := #[(`worker.a, 1), (`worker.b, 2)]
}

#guard vectorA.before vectorB
#guard !vectorB.before vectorA
#guard vectorA.concurrent vectorConcurrent

private def eventClock1 : EventClock := {
  event := `event.e1
  vector := some vectorA
  lamport := some { actor := `worker.a, counter := 1 }
  hybrid := some { actor := `worker.a, wallTime := 1000, logical := 0 }
}

private def eventClock3 : EventClock := {
  event := `event.e3
  vector := some vectorB
  lamport := some { actor := `worker.a, counter := 3 }
  hybrid := some { actor := `worker.a, wallTime := 1001, logical := 0 }
}

#guard eventClock1.consistentWith eventClock3 store.causal

run_cmd do
  unless store.valid do throwError "revision store validation failed"
  let snapshot ← match store.snapshotAt 3 with
    | .ok value => pure value
    | .error error => throwError error
  unless snapshot.size == 1 && snapshot[0]!.semanticallyEqual statusClosed do
    throwError "snapshot did not retain the latest asserted attributes"
  unless store.causal.before `event.e1 `event.e3 do
    throwError "causal transitive closure failed"
  unless Zil.Codec.Revision.roundTrips store do
    throwError "revision codec round trip failed"
