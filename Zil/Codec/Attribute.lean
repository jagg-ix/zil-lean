import Zil.Core.Attribute

namespace Zil.Codec

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if acc == Name.anonymous then Name.mkSimple part else Name.str acc part

private def escape (value : String) : String :=
  value.replace "%" "%25"
    |>.replace ";" "%3B"
    |>.replace "=" "%3D"
    |>.replace ":" "%3A"
    |>.replace "\t" "%09"
    |>.replace "\n" "%0A"

private def unescape (value : String) : String :=
  value.replace "%0A" "\n"
    |>.replace "%09" "\t"
    |>.replace "%3A" ":"
    |>.replace "%3D" "="
    |>.replace "%3B" ";"
    |>.replace "%25" "%"

/-- Stable scalar/term encoding for one attribute value. -/
def encodeAttrValue : Zil.AttrValue → String
  | .text value => "s:" ++ escape value
  | .integer value => "i:" ++ toString value
  | .decimal value => "d:" ++ escape value
  | .boolean value => "b:" ++ if value then "true" else "false"
  | .term (.var name) => "v:" ++ escape name.toString
  | .term (.node node) => "n:" ++ escape node.name.toString

/-- Decode one attribute value. -/
def decodeAttrValue (text : String) : Except String Zil.AttrValue := do
  match text.splitOn ":" with
  | ["s", payload] => pure (.text (unescape payload))
  | ["i", payload] =>
      let value ← payload.toInt?.toExcept s!"invalid integer attribute: {payload}"
      pure (.integer value)
  | ["d", payload] => pure (.decimal (unescape payload))
  | ["b", "true"] => pure (.boolean true)
  | ["b", "false"] => pure (.boolean false)
  | ["v", payload] => pure (.term (.variable (nameFromString (unescape payload))))
  | ["n", payload] => pure (.term (.ground (nameFromString (unescape payload))))
  | _ => throw s!"invalid attribute value: {text}"

/-- Encode an attribute map in deterministic source order. -/
def encodeAttributes (attrs : Array Zil.Attribute) : String :=
  String.intercalate ";" <| attrs.toList.map fun entry =>
    escape entry.key.toString ++ "=" ++ encodeAttrValue entry.value

/-- Decode an attribute map and reject duplicate keys. -/
def decodeAttributes (text : String) : Except String (Array Zil.Attribute) := do
  if text.isEmpty then return #[]
  let mut attrs : Array Zil.Attribute := #[]
  for token in text.splitOn ";" do
    let (keyText, valueText) ← match token.splitOn "=" with
      | [key, value] => pure (key, value)
      | _ => throw s!"invalid attribute entry: {token}"
    let entry : Zil.Attribute := {
      key := nameFromString (unescape keyText)
      value := ← decodeAttrValue valueText }
    attrs := attrs.push entry
  unless Zil.Attribute.keysUnique attrs do
    throw "duplicate attribute key"
  pure attrs

end Zil.Codec
