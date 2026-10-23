/-!
# Text rules of the Java library, as earlier ZIL tools relied on them

`clojure.string/trim` trims `Character.isWhitespace` characters, the regular expression class `\s` is narrower, and
`clojure.string/split-lines` splits on `\r?\n` and drops trailing empty strings. Tools that must give the same
answers as those functions share these definitions.
-/

namespace Zil.JavaText

/-- `java.lang.Character.isWhitespace`, which `clojure.string/trim` uses. -/
def isJavaWs (c : Char) : Bool :=
  let n := c.toNat
  n == 0x20 || (0x09 ≤ n && n ≤ 0x0D) || (0x1C ≤ n && n ≤ 0x1F) || n == 0x1680 ||
    (0x2000 ≤ n && n ≤ 0x2006) || (0x2008 ≤ n && n ≤ 0x200A) || n == 0x2028 || n == 0x2029 ||
    n == 0x205F || n == 0x3000

/-- The regular expression class `\s`. -/
def isReSpace (c : Char) : Bool := c == ' ' || (0x09 ≤ c.toNat && c.toNat ≤ 0x0D)

def jtrim (text : String) : String :=
  String.ofList ((text.toList.dropWhile isJavaWs).reverse.dropWhile isJavaWs).reverse

/-- `clojure.string/split-lines`: split on `\r?\n` and drop trailing empty strings (a text with no newline is one line). -/
def splitLines (text : String) : Array String := Id.run do
  let mut lines : Array String := #[]
  let mut current : List Char := []
  let mut sawNewline := false
  for c in text.toList do
    if c == '\n' then
      sawNewline := true
      let line := match current with | '\r' :: rest => rest | other => other
      lines := lines.push (String.ofList line.reverse)
      current := []
    else current := c :: current
  lines := lines.push (String.ofList current.reverse)
  if !sawNewline then return lines
  while !lines.isEmpty && lines.back!.isEmpty do lines := lines.pop
  return lines

/-- `Double.toString` of the double nearest to a plain decimal of at most 15 significant digits. -/
def javaDouble (text : String) : String :=
  let negative := text.startsWith "-"
  let body := if negative then String.ofList text.toList.tail! else text
  let (whole, fraction) := match body.splitOn "." with | [w, f] => (w, f) | _ => (body, "")
  let wholeTrimmed := String.ofList (whole.toList.dropWhile (· == '0'))
  let fractionTrimmed := String.ofList (fraction.toList.reverse.dropWhile (· == '0')).reverse
  let digits := wholeTrimmed ++ fractionTrimmed
  let sign := if negative then "-" else ""
  if digits.all (· == '0') then sign ++ "0.0"
  else
    -- decimal exponent of the first significant digit
    let leadingZerosInFraction := if wholeTrimmed.isEmpty then fractionTrimmed.length - (String.ofList (fractionTrimmed.toList.dropWhile (· == '0'))).length else 0
    let exponent : Int := if wholeTrimmed.isEmpty then -(leadingZerosInFraction : Int) - 1 else wholeTrimmed.length - 1
    let significant := String.ofList ((if wholeTrimmed.isEmpty then (fractionTrimmed.toList.dropWhile (· == '0')) else digits.toList).reverse.dropWhile (· == '0')).reverse
    if exponent ≥ -3 && exponent < 7 then
      let w := if wholeTrimmed.isEmpty then "0" else wholeTrimmed
      let f := if fractionTrimmed.isEmpty then "0" else fractionTrimmed
      sign ++ w ++ "." ++ f
    else
      let first := String.ofList (significant.toList.take 1)
      let rest := String.ofList (significant.toList.drop 1)
      sign ++ first ++ "." ++ (if rest.isEmpty then "0" else rest) ++ "E" ++ toString exponent

/-- A Clojure `pr-str` of a string. -/
def prString (value : String) : String := Id.run do
  let mut out := "\""
  for c in value.toList do
    out := out ++ match c with
      | '"' => "\\\"" | '\\' => "\\\\" | '\n' => "\\n" | '\t' => "\\t" | '\r' => "\\r"
      | '\x0C' => "\\f" | '\x08' => "\\b" | other => other.toString
  return out ++ "\""

end Zil.JavaText
