import Zil.Json.Ordered

/-!
# EDN reader

The request, payload and measurement files of the earlier tools were written in EDN. This reads the subset they used
(nil, booleans, integers, decimals, strings, keywords, symbols, lists, vectors, maps, sets, comments, `#_`) into the
canonical JSON form a control-plane record needs: a keyword or symbol becomes its name, a map becomes an object, a set
becomes an array ordered by the text of its elements. Tagged literals and characters are errors.
-/

namespace Zil.Edn

open Zil.Json

inductive Value where
  | nil
  | bool (value : Bool)
  | int (value : Int)
  | decimal (text : String)
  | str (value : String)
  | keyword (text : String)
  | symbol (text : String)
  | list (items : Array Value)
  | vector (items : Array Value)
  | map (entries : Array (Value × Value))
  | set (items : Array Value)
  deriving Inhabited

private structure Cursor where
  chars : Array Char
  pos : Nat

private abbrev Parser := StateT Cursor (Except String)

private def peek? : Parser (Option Char) := do
  let s ← get
  return s.chars[s.pos]?

private def peekAt? (offset : Nat) : Parser (Option Char) := do
  let s ← get
  return s.chars[s.pos + offset]?

private def advance : Parser Unit := modify fun s => { s with pos := s.pos + 1 }

/-- `text` without trailing copies of `c`. -/
private def stripSuffix (text : String) (c : Char) : String :=
  String.ofList (text.toList.reverse.dropWhile (· == c)).reverse

private def isSeparator (c : Char) : Bool :=
  c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t'

private def isDelimiter (c : Char) : Bool :=
  isSeparator c || c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' || c == '"' || c == ';'

private partial def skipTrivia : Parser Unit := do
  match ← peek? with
  | some c =>
      if isSeparator c then advance; skipTrivia
      else if c == ';' then
        let rec skipLine : Parser Unit := do
          match ← peek? with
          | some '\n' | none => pure ()
          | some _ => advance; skipLine
        skipLine
        skipTrivia
      else pure ()
  | none => pure ()

private partial def token : Parser String := do
  let mut text := ""
  repeat
    match ← peek? with
    | some c => if isDelimiter c then break else text := text.push c; advance
    | none => break
  return text

private partial def readString : Parser String := do
  advance
  let mut out := ""
  repeat
    match ← peek? with
    | none => throw "unterminated string"
    | some '"' => advance; break
    | some '\\' =>
        advance
        match ← peek? with
        | none => throw "unterminated escape"
        | some e =>
            advance
            match e with
            | 'n' => out := out.push '\n'
            | 't' => out := out.push '\t'
            | 'r' => out := out.push '\r'
            | '"' => out := out.push '"'
            | '\\' => out := out.push '\\'
            | 'u' =>
                let mut n := 0
                for _ in [0:4] do
                  match ← peek? with
                  | some h =>
                      let v := if h.isDigit then h.toNat - 48
                        else if 'a' ≤ h && h ≤ 'f' then h.toNat - 87
                        else if 'A' ≤ h && h ≤ 'F' then h.toNat - 55 else 100
                      if v > 15 then throw "invalid \\u escape"
                      n := n * 16 + v
                      advance
                  | none => throw "unterminated \\u escape"
                out := out.push (Char.ofNat n)
            | other => throw s!"unsupported string escape \\{other}"
    | some c => out := out.push c; advance
  return out

mutual
  private partial def readSequence (close : Char) : Parser (Array Value) := do
    let mut items := #[]
    repeat
      skipTrivia
      match ← peek? with
      | none => throw s!"expected '{close}'"
      | some c =>
          if c == close then advance; break
          else
            match ← readItem with
            | some v => items := items.push v
            | none => pure ()
    return items

  /-- One form, or `none` for a discarded `#_` form. -/
  private partial def readItem : Parser (Option Value) := do
    skipTrivia
    match ← peek? with
    | none => throw "unexpected end of text"
    | some '#' =>
        match ← peekAt? 1 with
        | some '_' =>
            advance; advance
            let _ ← readValue
            return none
        | some '{' =>
            advance; advance
            return some (.set (← readSequence '}'))
        | _ => throw "tagged literals are not supported"
    | _ => return some (← readValue)

  private partial def readValue : Parser Value := do
    skipTrivia
    match ← peek? with
    | none => throw "unexpected end of text"
    | some c =>
        if c == '"' then return .str (← readString)
        else if c == '[' then advance; return .vector (← readSequence ']')
        else if c == '(' then advance; return .list (← readSequence ')')
        else if c == '{' then
          advance
          let items ← readSequence '}'
          if items.size % 2 != 0 then throw "map literal has an odd number of forms"
          let mut entries := #[]
          for i in [0:items.size / 2] do
            entries := entries.push (items[2 * i]!, items[2 * i + 1]!)
          return .map entries
        else if c == '#' then
          match ← readItem with
          | some v => return v
          | none => readValue
        else if c == ')' || c == ']' || c == '}' then throw s!"unmatched '{c}'"
        else if c == '\\' then throw "character literals are not supported"
        else
          let text ← token
          if text == "nil" then return .nil
          else if text == "true" then return .bool true
          else if text == "false" then return .bool false
          else if text.startsWith ":" then
            if text.length == 1 then throw "empty keyword" else return .keyword (String.ofList text.toList.tail!)
          else
            let numeric := stripSuffix text 'N'
            match numeric.toInt? with
            | some n => if text.startsWith "+" then return .symbol text else return .int n
            | none =>
                match text.toList with
                | first :: rest =>
                    let startsNumber :=
                      first.isDigit || ((first == '-' || first == '+') && (rest.head?.map Char.isDigit).getD false)
                    if startsNumber then return .decimal (stripSuffix text 'M') else return .symbol text
                | [] => throw "empty token"
end

/-- Parse the first form of `text`. -/
def parse (text : String) : Except String Value :=
  match (do
    skipTrivia
    let value ← readValue
    skipTrivia
    if (← peek?).isSome then throw "unexpected text after the form"
    return value : Parser Value).run { chars := text.toList.toArray, pos := 0 } with
  | .ok (value, _) => .ok value
  | .error message => .error message

/-- The text `clojure.core/str` gives a value, used to order a set's elements. -/
partial def strText : Value → String
  | .nil => ""
  | .bool b => toString b
  | .int n => toString n
  | .decimal t => t
  | .str s => s
  | .keyword k => ":" ++ k
  | .symbol s => s
  | .list items => "(" ++ " ".intercalate (items.toList.map strText) ++ ")"
  | .vector items => "[" ++ " ".intercalate (items.toList.map strText) ++ "]"
  | .map entries => "{" ++ ", ".intercalate (entries.toList.map fun (k, v) => strText k ++ " " ++ strText v) ++ "}"
  | .set items => "#{" ++ " ".intercalate (items.toList.map strText) ++ "}"

/-- A map key as the canonical form writes it: strings stay, keywords and symbols give their name. -/
private def keyName : Value → Except String String
  | .str s => .ok s
  | .keyword k => .ok ((k.splitOn "/").getLast!)
  | .symbol s => .ok s
  | _ => .error "canonical map keys must be strings, keywords, or symbols"

/-- Canonical JSON of a value: names for keywords and symbols, sorted objects, sets as sorted distinct arrays. -/
partial def toJson : Value → Except String J
  | .nil => .ok .null
  | .bool b => .ok (.bool b)
  | .int n => .ok (.int n)
  | .decimal t => .ok (.number t)
  | .str s => .ok (.str s)
  | .keyword k => .ok (.str ((k.splitOn "/").getLast!))
  | .symbol s => .ok (.str s)
  | .list items | .vector items => do
      let mut out := #[]
      for item in items do out := out.push (← toJson item)
      return .arr out
  | .map entries => do
      let mut fields : Array (String × J) := #[]
      for (k, v) in entries do
        fields := fields.push (← keyName k, ← toJson v)
      Zil.Json.canonical (.obj fields)
  | .set items => do
      let ordered := items.qsort fun a b => compareKeys (strText a) (strText b) == .lt
      let mut out : Array J := #[]
      for item in ordered do
        let j ← toJson item
        if out.any (· == j) then throw "canonical set values collide after normalization"
        out := out.push j
      return .arr out

/-- Read EDN text straight to canonical JSON. -/
def readCanonical (text : String) : Except String J := do
  toJson (← parse text)

end Zil.Edn
