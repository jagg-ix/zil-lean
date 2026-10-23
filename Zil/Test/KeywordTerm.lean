import Zil.Native

open Zil Lean

/-!
# Keywords as terms

A token that starts with a colon, such as `:N`, is a keyword. Today it is rejected as an empty name segment. It now names
what it spells without the colon, so a value written `:N` and a value written `N` are the same term. Everything that
parses today keeps its name, and every other rejected token keeps its message.
-/

private def nameOf (token : String) : Option Name :=
  match Zil.Parser.termFromToken token with
  | .ok (.node node) => some node.name
  | _ => none

private def sameAsToday (token : String) : Bool :=
  match Zil.Parser.nameFromToken token with
  | .ok name => nameOf token == some name
  | .error _ => false

private def sameError (token : String) : Bool :=
  match Zil.Parser.termFromToken token, Zil.Parser.nameFromToken token with
  | .error fromTerm, .error fromName => fromTerm == fromName
  | _, _ => false

/-! ## Unchanged: tokens that parse today -/

#guard sameAsToday "doc:readme"
#guard sameAsToday "N"
#guard sameAsToday "value:north"
#guard nameOf "value:north" == some (Name.str (Name.mkSimple "value") "north")

/-! ## New: keywords -/

#guard nameOf ":N" == nameOf "N"
#guard nameOf ":N" == some (Name.mkSimple "N")
#guard nameOf ":north_east" == nameOf "north_east"
-- the colon is only dropped; a typed name after it is kept
#guard nameOf ":kind:thing" == nameOf "kind:thing"

/-! ## Unchanged: what stays an error -/

#guard sameError ":"
#guard sameError "::"
#guard sameError "::x"
#guard sameError ":x::y"
#guard sameError "a::b"
#guard sameError ""

/-! ## In tuples -/

private def attrValue (line : String) : Option Zil.AttrValue :=
  match Zil.Parser.parseTupleLine 1 line with
  | .ok tuple => tuple.attrs[0]? |>.map (·.value)
  | .error _ => none

#guard attrValue "a:b#c@d:e [move=:N]." == attrValue "a:b#c@d:e [move=N]."
#guard (attrValue "a:b#c@d:e [move=:N].").isSome
#guard (Zil.Parser.parseTupleLine 1 "a:b#c@:N.").toOption.isSome
#guard (Zil.Parser.parseTupleLine 1 "a:b#c@::N.").toOption.isNone
