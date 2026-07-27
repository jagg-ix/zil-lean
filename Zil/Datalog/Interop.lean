module

public import Zil.Datalog.Basic
public import Zil.Datalog.Relation
public meta import Zil.Datalog.Basic
public meta import Zil.Datalog.Relation

@[expose] public section

open Lean

namespace Zil.Datalog

/-- A Zanzibar userset has no lossless representation in the binary Datalog
atom model. Malformed tagged scalars are reported instead of silently changed. -/
inductive TupleInteropError where
  | relationSetSubject (object relation : Name)
  | malformedInteger (encoded : String)
  | malformedBoolean (encoded : String)
  deriving Repr, DecidableEq, Inhabited

def encodeValue : Value → String
  | .symbol value => "zil:symbol:" ++ value
  | .string value => "zil:string:" ++ value
  | .integer value => "zil:integer:" ++ toString value
  | .boolean value => "zil:boolean:" ++ if value then "true" else "false"

def payload (encoded : String) (prefixLength : Nat) : String :=
  (encoded.drop prefixLength).toString

def decodeValue (encoded : String) : Except TupleInteropError Value :=
  if encoded.startsWith "zil:symbol:" then
    .ok (.symbol (payload encoded 11))
  else if encoded.startsWith "zil:string:" then
    .ok (.string (payload encoded 11))
  else if encoded.startsWith "zil:integer:" then
    match (payload encoded 12).toInt? with
    | some value => .ok (.integer value)
    | none => .error (.malformedInteger encoded)
  else if encoded.startsWith "zil:boolean:" then
    match payload encoded 12 with
    | "true" => .ok (.boolean true)
    | "false" => .ok (.boolean false)
    | _ => .error (.malformedBoolean encoded)
  else
    /- Human-authored Zanzibar names remain useful to Datalog as symbols. -/
    .ok (.symbol encoded)

def encodeName (value : Value) : Name := .mkSimple (encodeValue value)

def decodeName (name : Name) : Except TupleInteropError Value :=
  decodeValue name.toString

def objectMetadataKey := "__zil_object"
def subjectMetadataKey := "__zil_subject"

def encodeAttrs (attrs : AtomAttrs) : Metadata :=
  attrs.map fun (key, value) => (key, encodeValue value)

def decodeMetadata : Metadata → Except TupleInteropError AtomAttrs
  | [] => .ok []
  | (key, encoded) :: rest => do
      let value ← decodeValue encoded
      return (key, value) :: (← decodeMetadata rest)

/-- Losslessly lower a ground Datalog atom into a direct Zanzibar tuple. The
caller supplies provenance because provenance belongs only to the relation model. -/
def Atom.toRelationTuple (atom : Atom) (origin : FactOrigin := .source) : RelationTuple := {
  object := encodeName atom.object
  relation := .mkSimple atom.relation
  subject := .node (encodeName atom.subject)
  metadata := [(objectMetadataKey, encodeValue atom.object),
    (subjectMetadataKey, encodeValue atom.subject)] ++ encodeAttrs atom.attrs
  origin
}

/-- Project a direct Zanzibar tuple into the Datalog model. Tuple provenance is
intentionally erased because `Atom` has no provenance field; usersets are rejected. -/
def RelationTuple.toAtom (tuple : RelationTuple) : Except TupleInteropError Atom := do
  let subjectName ← match tuple.subject with
    | .node name => .ok name
    | .relationSet object relation => .error (.relationSetSubject object relation)
  let objectEncoded := tuple.metadata.lookup objectMetadataKey |>.getD tuple.object.toString
  let subjectEncoded := tuple.metadata.lookup subjectMetadataKey |>.getD subjectName.toString
  let attrs := tuple.metadata.filter fun entry =>
    entry.1 != objectMetadataKey && entry.1 != subjectMetadataKey
  return {
    object := ← decodeValue objectEncoded
    relation := tuple.relation.toString
    subject := ← decodeValue subjectEncoded
    attrs := ← decodeMetadata attrs
  }

/-- Lift all representable tuples, stopping at the first explicit boundary error. -/
def TupleStore.toAtoms (store : TupleStore) : Except TupleInteropError (List Atom) :=
  store.tuples.mapM RelationTuple.toAtom

/-- Construct a relation snapshot from Datalog facts under one unified revision. -/
def TupleStore.ofAtoms (revision : KnowledgeRevision) (atoms : List Atom)
    (origin : FactOrigin := .source) : TupleStore :=
  { revision, tuples := atoms.map (·.toRelationTuple origin) }

end Zil.Datalog
