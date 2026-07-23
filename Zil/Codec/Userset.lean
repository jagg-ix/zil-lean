import Zil.Core.Userset

namespace Zil.Codec

private def tupleNameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if acc == Name.anonymous then Name.mkSimple part else Name.str acc part

private def encodeTupleTerm : Zil.Term → String
  | .var name => s!"var:{name}"
  | .node node => s!"node:{node.name}"

private def decodeTupleTerm (text : String) : Except String Zil.Term :=
  match text.splitOn ":" with
  | ["var", name] => .ok (.variable (tupleNameFromString name))
  | ["node", name] => .ok (.ground (tupleNameFromString name))
  | _ => .error s!"invalid tuple term: {text}"

/-- Stable encoding that preserves direct and userset subjects. -/
def encodeTuple (tuple : Zil.TupleExpr) : String :=
  match tuple.subject with
  | .direct subject =>
      String.intercalate "\t" #[
        "tuple", encodeTupleTerm tuple.object, toString tuple.relation,
        "direct", encodeTupleTerm subject]
  | .userset userset =>
      String.intercalate "\t" #[
        "tuple", encodeTupleTerm tuple.object, toString tuple.relation,
        "userset", toString userset.object.name, toString userset.relation]

/-- Decode the lossless tuple representation. -/
def decodeTuple (text : String) : Except String Zil.TupleExpr := do
  match text.splitOn "\t" with
  | ["tuple", object, relation, "direct", subject] =>
      pure <| .direct
        (← decodeTupleTerm object)
        (tupleNameFromString relation)
        (← decodeTupleTerm subject)
  | ["tuple", object, relation, "userset", usersetObject, usersetRelation] =>
      pure <| .withUserset
        (← decodeTupleTerm object)
        (tupleNameFromString relation)
        ⟨tupleNameFromString usersetObject⟩
        (tupleNameFromString usersetRelation)
  | _ => throw s!"invalid canonical tuple: {text}"

/-- Semantic round-trip check for original tuple data. -/
def tupleRoundTrips (tuple : Zil.TupleExpr) : Bool :=
  match decodeTuple (encodeTuple tuple) with
  | .ok decoded => tuple.semanticallyEqual decoded
  | .error _ => false

private def codecDirectGroup : Zil.TupleExpr :=
  .direct (.ground `doc.readme) `zil.viewer (.ground `group.eng)

private def codecMemberUserset : Zil.TupleExpr :=
  .withUserset (.ground `doc.readme) `zil.viewer ⟨`group.eng⟩ `zil.member

#guard !codecDirectGroup.semanticallyEqual codecMemberUserset
#guard tupleRoundTrips codecDirectGroup
#guard tupleRoundTrips codecMemberUserset
#guard codecMemberUserset.lower.facts.size == 1
#guard codecMemberUserset.lower.rules.size == 1

end Zil.Codec
