import Zil.Core.Term

namespace Zil

/-- Values accepted by tuple attributes. `term` supports named values and rule/query variables. -/
inductive AttrValue where
  | text : String → AttrValue
  | integer : Int → AttrValue
  | decimal : String → AttrValue
  | boolean : Bool → AttrValue
  | term : Term → AttrValue
  deriving Repr, BEq, Inhabited

namespace AttrValue

/-- Attribute values are ground unless they contain a variable term. -/
def isGround : AttrValue → Bool
  | .term term => !term.isVariable
  | _ => true

end AttrValue

/-- One key/value entry attached to a relation tuple. -/
structure Attribute where
  key : Name
  value : AttrValue
  deriving Repr, BEq, Inhabited

namespace Attribute

/-- Attribute arrays compare as finite maps, independent of source ordering. -/
def arraysSemanticallyEqual (left right : Array Attribute) : Bool :=
  left.size == right.size &&
  left.all (fun entry => right.any (fun candidate => candidate == entry))

/-- Attribute keys must be unique within one tuple. -/
def keysUnique (attrs : Array Attribute) : Bool :=
  attrs.all fun entry =>
    (attrs.filter fun candidate => candidate.key == entry.key).size == 1

/-- Every attribute value is ground. -/
def allGround (attrs : Array Attribute) : Bool :=
  attrs.all fun entry => entry.value.isGround

/-- Look up one attribute by key. -/
def find? (attrs : Array Attribute) (key : Name) : Option Attribute :=
  attrs.find? fun entry => entry.key == key

end Attribute

end Zil
