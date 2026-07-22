import Zil.Interop.Delta

open Zil

private def oldFact : RelExpr :=
  .mk' (.ground `lean.Delta.old) `zil.formalizes (.ground `claim.old)

private def newFact : RelExpr :=
  .mk' (.ground `lean.Delta.new) `zil.formalizes (.ground `claim.new)

private def snapshot : Zil.Interop.ExchangeEnvelope :=
  { knowledgeRevision := 5, facts := #[oldFact] }

private def delta : Zil.Interop.KnowledgeDelta :=
  { baseRevision := 5
    targetRevision := 6
    removeFacts := #[oldFact]
    addFacts := #[newFact] }

#guard match Zil.Interop.applyDelta snapshot delta with
  | .ok updated => updated.knowledgeRevision == 6 &&
      updated.facts.size == 1 && updated.facts[0]!.semanticallyEqual newFact
  | .error _ => false

#guard match Zil.Interop.applyDelta snapshot { delta with baseRevision := 4 } with
  | .error (.staleRevision 5 4) => true
  | _ => false

#guard match Zil.Interop.decodeDelta (Zil.Interop.encodeDelta delta) with
  | .ok decoded => decoded.baseRevision == 5 && decoded.targetRevision == 6 &&
      decoded.addFacts.size == 1 && decoded.removeFacts.size == 1
  | .error _ => false

#guard match Zil.Interop.composeDelta delta
    { baseRevision := 6, targetRevision := 7, addFacts := #[oldFact] } with
  | .ok combined => combined.baseRevision == 5 && combined.targetRevision == 7
  | .error _ => false