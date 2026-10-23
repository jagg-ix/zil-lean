import Zil.Json.Ordered
import Zil.Edn.Reader
import Zil.Util.JavaText

/-!
# Data formats for datasources and interop

One place that reads and writes the formats a datasource can deliver: JSON, EDN, plain text, CSV, a small YAML subset
and `key=value` lines. A payload becomes a `J` value; objects keep their keys in the order they were written.

The YAML reader is deliberately the small one the earlier tools had, not a YAML parser: a list of `- key: value` items or
a flat `key: value` document, with `#` comments, and anything that is JSON is read as JSON. Scalars are typed the way
they always were: `true`/`false`, integers, decimals, a double-quoted string (read as an EDN string), anything else text.
-/

namespace Zil.Runtime.Codec

open Zil.Json Zil.JavaText

inductive Format where
  | json | edn | text | csv | yaml | kv
  deriving BEq, Repr

def Format.name : Format → String
  | .json => "json" | .edn => "edn" | .text => "text" | .csv => "csv" | .yaml => "yaml" | .kv => "kv"

/-- The format a name denotes (`yml` is `yaml`), ignoring case and surrounding space. -/
def normalizeFormat (name : String) : Option Format :=
  match (jtrim name).toLower with
  | "json" => some .json | "edn" => some .edn | "text" => some .text | "csv" => some .csv
  | "yaml" | "yml" => some .yaml | "kv" => some .kv | _ => none

/-- Options come from a datasource's attributes (`csv_header`, `csv_typed`, `csv-delimiter`, `kv_typed`, `csv-columns`). -/
abbrev Opts := Array (String × J)

private def opt? (opts : Opts) (names : List String) : Option J :=
  names.findSome? fun name => opts.find? (·.1 == name) |>.map (·.2)

private def flag (opts : Opts) (names : List String) (default : Bool) : Bool :=
  match opt? opts names with
  | some (.bool b) => b
  | some (.str s) => s != "false"
  | some .null => false
  | some _ => true
  | none => default

private def optText (opts : Opts) (names : List String) : Option String :=
  match opt? opts names with
  | some (.str s) => some s
  | _ => none

/-! ## Values the way the earlier tools printed them -/

/-- `Double.toString` of a JSON or decimal number written with an optional exponent. -/
def javaNumber (text : String) : String :=
  let negative := text.startsWith "-"
  let body := (if negative then text.drop 1 else text.toSubstring.toString.toSlice).toString
  let lower := body.toLower
  let (mantissa, exponent) := match lower.splitOn "e" with
    | [m, e] => (m, (if e.startsWith "+" then (e.drop 1).toString else e).toInt?.getD 0)
    | _ => (lower, (0 : Int))
  let (whole, fraction) := match mantissa.splitOn "." with | [w, f] => (w, f) | _ => (mantissa, "")
  let digits := whole ++ fraction
  let pointAt : Int := whole.length + exponent
  let plain :=
    if pointAt ≤ 0 then "0." ++ String.ofList (List.replicate (-pointAt).toNat '0') ++ digits
    else if pointAt ≥ digits.length then digits ++ String.ofList (List.replicate (pointAt - digits.length).toNat '0') ++ ".0"
    else (digits.take pointAt.toNat).toString ++ "." ++ (digits.drop pointAt.toNat).toString
  javaDouble ((if negative then "-" else "") ++ plain)

/-- `pr-str` of a value whose map keys are keywords. -/
partial def prStr : J → String
  | .null => "nil"
  | .bool b => toString b
  | .int n => toString n
  | .number t => javaNumber t
  | .str s => prString s
  | .arr items => "[" ++ " ".intercalate (items.toList.map prStr) ++ "]"
  | .obj fields => "{" ++ ", ".intercalate (fields.toList.map fun (k, v) => ":" ++ k ++ " " ++ prStr v) ++ "}"

/-- `clojure.core/str` of a value. -/
def clojureStr : J → String
  | .null => ""
  | .str s => s
  | value => prStr value

/-- Objects with a repeated key keep the first position and the last value, as a map built by `assoc` does. -/
partial def dedupe : J → J
  | .arr items => .arr (items.map dedupe)
  | .obj fields =>
      let merged := fields.foldl (init := (#[] : Array (String × J))) fun acc (key, value) =>
        let value := dedupe value
        match acc.findIdx? (·.1 == key) with
        | some index => acc.set! index (key, value)
        | none => acc.push (key, value)
      .obj merged
  | other => other

/-- Decimal numbers are doubles, written the way `Double.toString` writes them. -/
partial def javaNumbers : J → J
  | .number t => .number (javaNumber t)
  | .arr items => .arr (items.map javaNumbers)
  | .obj fields => .obj (fields.map fun (k, v) => (k, javaNumbers v))
  | other => other

def recordsFromDecoded : J → Array J
  | .null => #[]
  | .arr items => items
  | other => #[other]

/-! ## Scalars -/

private def allDigits (s : String) : Bool := !s.isEmpty && s.all fun c => c.isDigit && c.toNat < 128

private def isIntegerToken (t : String) : Bool :=
  allDigits (if t.startsWith "-" then (t.drop 1).toString else t)

private def isDecimalToken (t : String) : Bool :=
  match (if t.startsWith "-" then (t.drop 1).toString else t).splitOn "." with
  | [w, f] => allDigits w && allDigits f
  | _ => false

/-- A double-quoted token whose every inner quote is escaped. -/
private def isQuotedToken (t : String) : Bool :=
  let chars := t.toList.toArray
  chars.size ≥ 2 && chars[0]! == '"' && chars[chars.size - 1]! == '"' &&
    (List.range (chars.size - 2)).all fun i => chars[i + 1]! != '"' || (i ≥ 1 && chars[i]! == '\\')

private def longMin : Int := -9223372036854775808
private def longMax : Int := 9223372036854775807

/-- The typed reading of one token. -/
def parseScalarToken (raw : String) : Except String J :=
  let t := jtrim raw
  if t.isEmpty then .ok (.str "")
  else if t.toLower == "true" then .ok (.bool true)
  else if t.toLower == "false" then .ok (.bool false)
  else if isIntegerToken t then
    match t.toInt? with
    | some n => if longMin ≤ n && n ≤ longMax then .ok (.int n) else .error s!"For input string: \"{t}\""
    | none => .error s!"For input string: \"{t}\""
  else if isDecimalToken t then .ok (.number (javaNumber t))
  else if isQuotedToken t then
    match Zil.Edn.parse t with
    | .ok (.str s) => .ok (.str s)
    | _ => .error s!"Invalid escape sequence in quoted string token: {t}"
  else .ok (.str t)

/-- A header cell as a key: lower case, other characters collapsed to `_`, edge underscores dropped, `col_N` if empty. -/
private def sanitizeHeaderKey (cell : String) (index : Nat) : String := Id.run do
  let cleaned := (jtrim cell).toLower
  let mut out := ""
  let mut inRun := false
  for c in cleaned.toList do
    if (c.isLower || c.isDigit) && c.toNat < 128 || c == '_' || c == ':' || c == '-' || c == '.' then
      out := out.push c
      inRun := false
    else
      unless inRun do out := out.push '_'
      inRun := true
  let trimmed := String.ofList ((out.toList.dropWhile (· == '_')).reverse.dropWhile (· == '_')).reverse
  if trimmed.toList.all isJavaWs then s!"col_{index + 1}" else trimmed

/-! ## CSV -/

private def csvSplitLine (line : String) (delimiter : Char) : Array String := Id.run do
  let chars := line.toList.toArray
  let mut out : Array String := #[]
  let mut token := ""
  let mut inQuote := false
  let mut i := 0
  while i < chars.size do
    let c := chars[i]!
    let next := chars[i + 1]?
    if inQuote then
      if c == '"' then
        if next == some '"' then
          token := token.push '"'
          i := i + 2
        else
          inQuote := false
          i := i + 1
      else
        token := token.push c
        i := i + 1
    else if c == '"' then
      inQuote := true
      i := i + 1
    else if c == delimiter then
      out := out.push token
      token := ""
      i := i + 1
    else
      token := token.push c
      i := i + 1
  return out.push token

private def delimiterOf (opts : Opts) : Char :=
  match optText opts ["csv-delimiter", "csv_delimiter"] with
  | some s => s.toList.head?.getD ','
  | none => ','

private def parseCsv (text : String) (opts : Opts) : Except String J := do
  let header := flag opts ["csv_header", "csv-header"] true
  let typed := flag opts ["csv_typed", "csv-typed"] true
  let delimiter := delimiterOf opts
  let lines := (splitLines text).filter fun line => !line.toList.all isJavaWs
  let rows := lines.map (csvSplitLine · delimiter)
  if rows.isEmpty then return .arr #[]
  let width := rows.foldl (fun acc row => max acc row.size) 0
  let padded := rows.map fun row => row ++ Array.replicate (width - row.size) ""
  let coerce (cell : String) : Except String J := if typed then parseScalarToken cell else pure (.str cell)
  let build (keys : Array String) (row : Array String) : Except String J := do
    let mut fields : Array (String × J) := #[]
    for (key, cell) in keys.zip row do
      fields := fields.push (key, ← coerce cell)
    return dedupe (.obj fields)
  if header then
    let keys := padded[0]!.mapIdx fun index cell => sanitizeHeaderKey cell index
    return .arr (← (padded.extract 1 padded.size).mapM (build keys))
  else
    let keys := (List.range width).toArray.map fun index => s!"col_{index + 1}"
    return .arr (← padded.mapM (build keys))

private def csvEscape (value : String) (delimiter : Char) : String :=
  let needsQuote := value.contains delimiter || value.contains '"' || value.contains '\n' || value.contains '\r'
  if needsQuote then "\"" ++ value.replace "\"" "\"\"" ++ "\"" else value

private def emitCsv (value : J) (opts : Opts) : String :=
  let delimiter := delimiterOf opts
  let rows : Array J := match value with
    | .null => #[]
    | .obj _ => #[value]
    | .arr items => if items.all (match · with | .obj _ => true | _ => false) then items else items.map fun v => .obj #[("value", v)]
    | other => #[.obj #[("value", other)]]
  let columns : Array String :=
    match opt? opts ["csv-columns", "csv_columns"] with
    | some (.arr names) => names.map clojureStr
    | _ =>
        let keys := rows.foldl (init := (#[] : Array String)) fun acc row =>
          match row with
          | .obj fields => fields.foldl (fun acc (k, _) => if acc.contains k then acc else acc.push k) acc
          | _ => acc
        keys.qsort fun a b => compareKeys a b == .lt
  if rows.isEmpty then ""
  else
    let sep := delimiter.toString
    let headerLine := sep.intercalate (columns.toList.map (csvEscape · delimiter))
    let body := rows.toList.map fun row =>
      sep.intercalate (columns.toList.map fun key =>
        csvEscape (match row.get? key with | none => "" | some .null => "" | some v => clojureStr v) delimiter)
    "\n".intercalate (headerLine :: body)

/-! ## YAML (the small subset), key=value -/

private def isKeyChar (c : Char) : Bool :=
  (c.isAlphanum && c.toNat < 128) || c == '_' || c == ':' || c == '-' || c == '.'

/-- `\s*([A-Za-z0-9_:\-\.]+)\s*:\s*(.*?)\s*$` against a whole line: the key (lower case) and the value text. -/
private def yamlKvLine (line : String) : Option (String × String) :=
  let chars := (line.toList.dropWhile isReSpace)
  let run := chars.takeWhile isKeyChar
  (List.range run.length).reverse.findSome? fun index =>
    let length := index + 1
    let rest := (chars.drop length).dropWhile isReSpace
    match rest with
    | ':' :: value =>
        let value := (value.dropWhile isReSpace)
        let value := String.ofList ((value.reverse.dropWhile isReSpace).reverse)
        some (String.ofList (chars.take length)).toLower |>.map (·, value)
    | _ => none

private def yamlScalar (raw : String) : Except String J :=
  let t := jtrim raw
  if t.isEmpty || t == "null" then .ok .null else parseScalarToken t

private def parseYamlList (lines : Array String) : Except String J := do
  let mut out : Array J := #[]
  let mut current : Option J := none
  for line in lines do
    let trimmed := jtrim line
    if trimmed.startsWith "- " then
      if let some value := current then
        if value != .null then out := out.push value
      let item := (trimmed.drop 2).toString
      match yamlKvLine item with
      | some (key, value) => current := some (.obj #[(key, ← yamlScalar value)])
      | none => current := some (← yamlScalar item)
    else
      match current, yamlKvLine trimmed with
      | some (.obj fields), some (key, value) =>
          current := some (dedupe (.obj (fields.push (key, ← yamlScalar value))))
      | _, _ => pure ()
  if let some value := current then
    if value != .null then out := out.push value
  return .arr out

/-- Text after whitespace followed by `#` is a comment. -/
private def stripYamlComment (line : String) : String :=
  let chars := line.toList.toArray
  match (List.range chars.size).find? (fun k => chars[k]! == '#' && k > 0 && isReSpace chars[k - 1]!) with
  | none => line
  | some k =>
      let start := (List.range k).reverse.foldl (fun acc i => if acc == i + 1 && isReSpace chars[i]! then i else acc) k
      String.ofList (chars.toList.take start)

private def parseYaml (text : String) : Except String J := do
  let trimmedStart := String.ofList (text.toList.dropWhile isJavaWs)
  if trimmedStart.startsWith "{" || trimmedStart.startsWith "[" then
    match Zil.Json.parse text with
    | .ok value => return dedupe value
    | .error _ => pure ()
  let lines := (splitLines text).map (fun line => String.ofList ((stripYamlComment line).toList.reverse.dropWhile isJavaWs).reverse)
    |>.filter fun line => !line.toList.all isJavaWs
  if lines.isEmpty then return .arr #[]
  if (jtrim lines[0]!).startsWith "- " then parseYamlList lines
  else
    let mut fields : Array (String × J) := #[]
    for line in lines do
      if let some (key, value) := yamlKvLine line then fields := fields.push (key, ← yamlScalar value)
    return dedupe (.obj fields)

private def parseKv (text : String) (opts : Opts) : Except String J := do
  let typed := flag opts ["kv_typed", "kv-typed"] true
  let mut fields : Array (String × J) := #[]
  for line in splitLines text do
    let trimmed := jtrim line
    if !trimmed.isEmpty && !trimmed.startsWith "#" && trimmed.contains '=' then
      match trimmed.splitOn "=" with
      | key :: rest =>
          let value := "=".intercalate rest
          let parsed ← if typed then parseScalarToken value else pure (.str value)
          fields := fields.push ((jtrim key).toLower, parsed)
      | [] => pure ()
  return dedupe (.obj fields)

private def yamlEscape (value : J) : String :=
  let s := match value with
    | .null => "null"
    | .bool b => toString b
    | .int n => toString n
    | .number t => javaNumber t
    | .str s => s
    | other => prStr other
  if s.toList.all isJavaWs || s.any (fun c => c == '#' || c == ':' || c == '\n' || c == '\r' || c == '"')
      || s.startsWith " " || s.endsWith " " then
    "\"" ++ s.replace "\"" "\\\"" ++ "\""
  else s

private def sortedFields (fields : Array (String × J)) : Array (String × J) :=
  fields.qsort fun a b => compareKeys a.1 b.1 == .lt

private def emitYaml (value : J) : String :=
  match value with
  | .null => "null"
  | .obj fields => "\n".intercalate ((sortedFields fields).toList.map fun (k, v) => k ++ ": " ++ yamlEscape v)
  | .arr items =>
      "\n".intercalate (items.toList.map fun item =>
        match item with
        | .obj fields =>
            match (sortedFields fields).toList with
            | [] => "- "
            | (k0, v0) :: rest =>
                "\n".intercalate (("- " ++ k0 ++ ": " ++ yamlEscape v0) :: rest.map fun (k, v) => "  " ++ k ++ ": " ++ yamlEscape v)
        | other => "- " ++ yamlEscape other)
  | other => yamlEscape other

private def emitKv (value : J) : String :=
  let fields := match value with | .obj fields => fields | other => #[("value", other)]
  "\n".intercalate ((sortedFields fields).toList.map fun (k, v) =>
    k ++ "=" ++ (match v with | .null => "" | .str s => s | other => clojureStr other))

/-! ## Entry points -/

private partial def ednToJ : Zil.Edn.Value → Except String J
  | .nil => .ok .null
  | .bool b => .ok (.bool b)
  | .int n => .ok (.int n)
  | .decimal t => .ok (.number t)
  | .str s => .ok (.str s)
  | .keyword k => .ok (.str ((k.splitOn "/").getLast!))
  | .symbol s => .ok (.str s)
  | .list items | .vector items | .set items => do
      let mut out : Array J := #[]
      for item in items do out := out.push (← ednToJ item)
      return .arr out
  | .map entries => do
      let mut fields : Array (String × J) := #[]
      for (k, v) in entries do
        let key ← match k with
          | .str s => pure s
          | .keyword s => pure ((s.splitOn "/").getLast!)
          | .symbol s => pure s
          | _ => throw "map keys must be strings, keywords or symbols"
        fields := fields.push (key, ← ednToJ v)
      return dedupe (.obj fields)

/-- Read a payload in `format`. -/
def parseString (format : Format) (text : String) (opts : Opts := #[]) : Except String J :=
  match format with
  | .json => (javaNumbers ∘ dedupe) <$> Zil.Json.parse text
  | .edn => do ednToJ (← Zil.Edn.parse text)
  | .text => .ok (.str text)
  | .csv => parseCsv text opts
  | .yaml => parseYaml text
  | .kv => parseKv text opts

/-- Write a value in `format`. -/
def emitString (format : Format) (value : J) (opts : Opts := #[]) : String :=
  match format with
  | .json => write value
  | .edn => prStr value
  | .text => match value with | .str s => s | other => prStr other
  | .csv => emitCsv value opts
  | .yaml => emitYaml value
  | .kv => emitKv value

end Zil.Runtime.Codec
