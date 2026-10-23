/-!
# JSON with ordered objects

`Lean.Json` keeps object fields sorted by key. Hash-chained records need the exact bytes of a document whose fields are in
a defined order, so this small type keeps fields in the order they were built or parsed, and its writer produces the same
bytes as `clojure.data.json/write-str`: non-ASCII as lowercase `\uXXXX` UTF-16 units, `/` escaped unless asked not to,
DEL written raw. That byte compatibility is what lets a store written by the removed Clojure runtime be verified here.
-/

namespace Zil.Json

inductive J where
  | null
  | bool (value : Bool)
  | int (value : Int)
  /-- A number that is not an integer, kept as the text it was written with. -/
  | number (text : String)
  | str (value : String)
  | arr (items : Array J)
  | obj (fields : Array (String × J))
  deriving Repr, BEq, Inhabited

namespace J

partial def beq : J → J → Bool
  | null, null => true
  | bool a, bool b => a == b
  | int a, int b => a == b
  | number a, number b => a == b
  | str a, str b => a == b
  | arr a, arr b => a.size == b.size && (a.zip b).all fun (x, y) => beq x y
  | obj a, obj b => a.size == b.size && (a.zip b).all fun ((k, x), (l, y)) => k == l && beq x y
  | _, _ => false

/-- The value of field `key` of an object. -/
def get? (value : J) (key : String) : Option J :=
  match value with
  | obj fields => fields.find? (·.1 == key) |>.map (·.2)
  | _ => none

def getStr? (value : J) (key : String) : Option String :=
  match value.get? key with
  | some (str text) => some text
  | _ => none

def getInt? (value : J) (key : String) : Option Int :=
  match value.get? key with
  | some (int n) => some n
  | _ => none

def asStr? : J → Option String
  | str text => some text
  | _ => none

def asArr? : J → Option (Array J)
  | arr items => some items
  | _ => none

end J

/-- UTF-16 code units of a character. -/
private def utf16Units (c : Char) : List UInt32 :=
  let n := c.toNat
  if n < 0x10000 then [n.toUInt32]
  else
    let m := n - 0x10000
    [(0xd800 + (m >>> 10)).toUInt32, (0xdc00 + (m &&& 0x3ff)).toUInt32]

private def hex4 (n : UInt32) : String :=
  let digit (v : UInt32) : Char := if v < 10 then Char.ofNat (48 + v.toNat) else Char.ofNat (87 + v.toNat)
  String.ofList [digit ((n >>> 12) &&& 15), digit ((n >>> 8) &&& 15), digit ((n >>> 4) &&& 15), digit (n &&& 15)]

/-- JSON text of a string, escaped as `clojure.data.json` writes it. -/
def writeString (text : String) (escapeSlash : Bool := true) : String := Id.run do
  let mut out := "\""
  for c in text.toList do
    let n := c.toNat
    if c == '"' then out := out ++ "\\\""
    else if c == '\\' then out := out ++ "\\\\"
    else if c == '/' then out := out ++ (if escapeSlash then "\\/" else "/")
    else if n == 8 then out := out ++ "\\b"
    else if n == 12 then out := out ++ "\\f"
    else if n == 10 then out := out ++ "\\n"
    else if n == 13 then out := out ++ "\\r"
    else if n == 9 then out := out ++ "\\t"
    else if n < 32 then out := out ++ "\\u" ++ hex4 n.toUInt32
    else if n < 127 || n == 127 then out := out.push c
    else
      for unit in utf16Units c do
        out := out ++ "\\u" ++ hex4 unit
  return out ++ "\""

/-- Compact JSON text, fields in their stored order. -/
partial def write (value : J) (escapeSlash : Bool := true) : String :=
  match value with
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int n => toString n
  | .number text => text
  | .str text => writeString text escapeSlash
  | .arr items => "[" ++ ",".intercalate (items.toList.map (write · escapeSlash)) ++ "]"
  | .obj fields =>
      "{" ++ ",".intercalate (fields.toList.map fun (k, v) => writeString k escapeSlash ++ ":" ++ write v escapeSlash) ++ "}"

/-! ## Parsing -/

private structure Cursor where
  chars : Array Char
  pos : Nat

private abbrev Parser := StateT Cursor (Except String)

private def peek? : Parser (Option Char) := do
  let s ← get
  return s.chars[s.pos]?

private def advance : Parser Unit := modify fun s => { s with pos := s.pos + 1 }

private partial def skipSpace : Parser Unit := do
  match ← peek? with
  | some c => if c == ' ' || c == '\n' || c == '\r' || c == '\t' then advance; skipSpace else pure ()
  | none => pure ()

private def expect (c : Char) : Parser Unit := do
  match ← peek? with
  | some d => if c == d then advance else throw s!"expected '{c}' but found '{d}'"
  | none => throw s!"expected '{c}' but the text ended"

private def hexValue? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - 48)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 87)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 55)
  else none

private def parseHex4 : Parser Nat := do
  let mut n := 0
  for _ in [0:4] do
    match ← peek? with
    | some c =>
        match hexValue? c with
        | some v => n := n * 16 + v; advance
        | none => throw "invalid \\u escape"
    | none => throw "unterminated \\u escape"
  return n

private partial def parseStringBody (acc : Array Char) (pendingHigh : Option Nat) : Parser String := do
  match ← peek? with
  | none => throw "unterminated string"
  | some '"' =>
      advance
      if pendingHigh.isSome then throw "unpaired surrogate" else pure (String.ofList acc.toList)
  | some '\\' =>
      advance
      match ← peek? with
      | none => throw "unterminated escape"
      | some e =>
          advance
          if e == 'u' then
            let n ← parseHex4
            match pendingHigh with
            | some high =>
                if 0xdc00 ≤ n && n < 0xe000 then
                  let cp := 0x10000 + ((high - 0xd800) <<< 10) + (n - 0xdc00)
                  parseStringBody (acc.push (Char.ofNat cp)) none
                else throw "unpaired surrogate"
            | none =>
                if 0xd800 ≤ n && n < 0xdc00 then parseStringBody acc (some n)
                else if 0xdc00 ≤ n && n < 0xe000 then throw "unpaired surrogate"
                else parseStringBody (acc.push (Char.ofNat n)) none
          else
            if pendingHigh.isSome then throw "unpaired surrogate"
            let c ← match e with
              | '"' => pure '"' | '\\' => pure '\\' | '/' => pure '/'
              | 'b' => pure (Char.ofNat 8) | 'f' => pure (Char.ofNat 12)
              | 'n' => pure '\n' | 'r' => pure '\r' | 't' => pure '\t'
              | other => throw s!"invalid escape \\{other}"
            parseStringBody (acc.push c) none
  | some c =>
      advance
      if pendingHigh.isSome then throw "unpaired surrogate"
      parseStringBody (acc.push c) none

private def parseString : Parser String := do
  expect '"'
  parseStringBody #[] none

private partial def parseNumber : Parser J := do
  let mut text := ""
  repeat
    match ← peek? with
    | some c =>
        if c.isDigit || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E' then
          text := text.push c
          advance
        else break
    | none => break
  if text.isEmpty then throw "expected a number"
  match text.toInt? with
  | some n => if text.startsWith "+" then throw s!"invalid number {text}" else pure (.int n)
  | none => pure (.number text)

private partial def parseValue : Parser J := do
  skipSpace
  match ← peek? with
  | none => throw "unexpected end of text"
  | some '{' =>
      advance
      skipSpace
      if (← peek?) == some '}' then
        advance
        return .obj #[]
      let mut fields : Array (String × J) := #[]
      repeat
        skipSpace
        let key ← parseString
        skipSpace
        expect ':'
        let value ← parseValue
        fields := fields.push (key, value)
        skipSpace
        match ← peek? with
        | some ',' => advance
        | some '}' => advance; break
        | _ => throw "expected ',' or '}'"
      return .obj fields
  | some '[' =>
      advance
      skipSpace
      if (← peek?) == some ']' then
        advance
        return .arr #[]
      let mut items : Array J := #[]
      repeat
        let value ← parseValue
        items := items.push value
        skipSpace
        match ← peek? with
        | some ',' => advance
        | some ']' => advance; break
        | _ => throw "expected ',' or ']'"
      return .arr items
  | some '"' => return .str (← parseString)
  | some c =>
      if c == 't' || c == 'f' || c == 'n' then
        let s ← get
        let rest := String.ofList (s.chars.toList.drop s.pos |>.take 5)
        if rest.startsWith "true" then
          modify fun s => { s with pos := s.pos + 4 }
          return .bool true
        else if rest.startsWith "false" then
          modify fun s => { s with pos := s.pos + 5 }
          return .bool false
        else if rest.startsWith "null" then
          modify fun s => { s with pos := s.pos + 4 }
          return .null
        else throw s!"unexpected '{c}'"
      else if c == '-' || c.isDigit then parseNumber
      else throw s!"unexpected '{c}'"

/-- Parse one JSON document, keeping the order of object fields. -/
def parse (text : String) : Except String J :=
  match (do
    let value ← parseValue
    skipSpace
    if (← peek?).isSome then throw "unexpected text after the document"
    return value : Parser J).run { chars := text.toList.toArray, pos := 0 } with
  | .ok (value, _) => .ok value
  | .error message => .error message

/-! ## Canonical form -/

/-- UTF-16 code unit sequence of a string, the order `clojure.core/compare` gives strings. -/
private def utf16Key (text : String) : List UInt32 := text.toList.flatMap utf16Units

/-- `compare` on strings as the JVM orders them. -/
def compareKeys (a b : String) : Ordering :=
  let rec go : List UInt32 → List UInt32 → Ordering
    | [], [] => .eq
    | [], _ => .lt
    | _, [] => .gt
    | x :: xs, y :: ys => if x < y then .lt else if y < x then .gt else go xs ys
  go (utf16Key a) (utf16Key b)

/-- Sort the fields of every object by key, recursively, as the canonical form of a record requires. Duplicate keys are
an error. -/
partial def canonical (value : J) : Except String J :=
  match value with
  | .arr items => do
      let mut out := #[]
      for item in items do out := out.push (← canonical item)
      return .arr out
  | .obj fields => do
      let mut out : Array (String × J) := #[]
      for (key, item) in fields do
        if out.any (·.1 == key) then throw s!"canonical map keys collide: {key}"
        out := out.push (key, ← canonical item)
      return .obj (out.qsort fun a b => compareKeys a.1 b.1 == .lt)
  | other => return other

end Zil.Json
