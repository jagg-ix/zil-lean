namespace Zil.Parser.Continuation

/-!
# Continuation lines

A statement may be written over several physical lines. The parsers read one logical line per statement, so this module
joins the physical lines of a statement into one logical line before they run.

A statement continues onto the next line when it is visibly unfinished:

* a `FIND` that does not yet end with `.` (the legacy frontend does the same): `FIND ?x` then `WHERE ...`;
* a rule premise (`IF ...`) followed by a line that starts with `AND `, or ending with a trailing `AND`;
* an open `[`, outside double quotes: a `QUERY_PACK`, a `DSL_PROFILE`, an attribute list.

Nothing that parses today changes, because a line that today parses is a complete statement and none of these applies. A
statement that is still unfinished when the next statement starts (or the input ends) is not joined at all, so the error is
the one it gives today, on the line where the statement began. Joined lines keep the number of their first physical line.
-/

private def clean (text : String) : String := text.trimAscii.toString

/-- The text before a `//` that is outside double quotes. -/
def stripLineComment (text : String) : String := Id.run do
  let mut kept : List Char := []
  let mut inQuote := false
  let mut escaped := false
  let mut previous : Option Char := none
  for char in text.toList do
    if inQuote then
      kept := char :: kept
      if escaped then escaped := false
      else if char == '\\' then escaped := true
      else if char == '"' then inQuote := false
    else if char == '/' && previous == some '/' then
      -- the first slash is already kept; drop it and stop
      kept := kept.drop 1
      return String.ofList kept.reverse
    else
      kept := char :: kept
      if char == '"' then inQuote := true
    previous := some char
  return String.ofList kept.reverse

/-- Net number of `[` minus `]` outside double quotes. A backslash inside quotes escapes the next character. -/
def bracketDepth (text : String) : Int := Id.run do
  let mut depth : Int := 0
  let mut inQuote := false
  let mut escaped := false
  for char in text.toList do
    if inQuote then
      if escaped then escaped := false
      else if char == '\\' then escaped := true
      else if char == '"' then inQuote := false
    else if char == '"' then inQuote := true
    else if char == '[' then depth := depth + 1
    else if char == ']' then depth := depth - 1
  return depth

/-- The first words that begin a statement; an unfinished statement never reaches past one of them. -/
private def startsAStatement (trimmed : String) : Bool :=
  ["RULE ", "QUERY ", "QUERY_PACK ", "DSL_PROFILE ", "MODULE ", "IF ", "THEN ", "FIND "].any fun word => trimmed.startsWith word

private def endsWithDot (text : String) : Bool := (clean (stripLineComment text)).endsWith "."

/-- Join the physical lines of each statement. The result lists, for each logical line, the index of its first physical line
and its text. A line that continues nothing is returned exactly as it was read. -/
def joinContinuations (texts : Array String) : Array (Nat × String) := Id.run do
  let mut out : Array (Nat × String) := #[]
  let mut i := 0
  while i < texts.size do
    let first := texts[i]!
    let head := clean first
    let isIf := head.startsWith "IF "
    let isFind := head.startsWith "FIND "
    let mut joined := clean (stripLineComment first)
    let mut j := i + 1
    let mut absorbing := true
    while absorbing && j < texts.size do
      let next := clean (stripLineComment texts[j]!)
      let findOpen := isFind && !endsWithDot joined
      let bracketOpen := bracketDepth joined > 0
      let andFollows := isIf && next.startsWith "AND "
      let andTrails := isIf && joined.endsWith " AND" && !startsAStatement next
      if andFollows || andTrails || ((findOpen || bracketOpen) && !startsAStatement next) then
        joined := joined ++ " " ++ next
        j := j + 1
      else
        absorbing := false
    let unfinished := (isFind && !endsWithDot joined) || bracketDepth joined > 0
    if j > i + 1 && !unfinished then
      out := out.push (i, joined)
      i := j
    else
      out := out.push (i, first)
      i := i + 1
  return out

end Zil.Parser.Continuation
