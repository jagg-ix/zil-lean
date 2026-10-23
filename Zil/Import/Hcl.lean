import Zil.Json.Ordered

/-!
# HCL / OpenTofu import

Reads the practical subset of HCL that describes infrastructure (`terraform`, `required_providers`, `provider`,
`resource`, `data`, `module`, `variable`, `output` blocks and their top-level scalar attributes) and writes ZIL source:
a `PROVIDER` declaration per provider and one fact group per block. Nested objects and lists are skipped, as before.
-/

namespace Zil.Import.Hcl

open Zil.Json

/-! ## Text helpers -/

private def isIdentChar (c : Char) : Bool := c.isAlphanum || c == '_' || c == '-'

private def trimText (s : String) : String :=
  let chars := s.toList.dropWhile Char.isWhitespace
  String.ofList (chars.reverse.dropWhile Char.isWhitespace).reverse

private def blank (s : String) : Bool := s.all Char.isWhitespace

/-- Lines as `clojure.string/split-lines` gives them: split on `\n` or `\r\n`, dropping trailing empty lines. -/
private def splitLines (s : String) : List String :=
  let parts := (s.splitOn "\n").map fun l => if l.endsWith "\r" then String.ofList l.toList.dropLast else l
  (parts.reverse.dropWhile (· == "")).reverse

/-- The line up to the first `#` or `//` outside a double-quoted string. -/
def stripInlineComment (line : String) : String := Id.run do
  let chars := line.toList.toArray
  let mut out := ""
  let mut inString := false
  let mut escape := false
  let mut i := 0
  while i < chars.size do
    let c := chars[i]!
    if escape then
      out := out.push c
      escape := false
    else if inString then
      out := out.push c
      if c == '\\' then escape := true
      else if c == '"' then inString := false
    else if c == '"' then
      out := out.push c
      inString := true
    else if c == '#' then return out
    else if c == '/' && chars[i + 1]? == some '/' then return out
    else out := out.push c
    i := i + 1
  return out

/-- Net braces opened by a line, ignoring those inside strings. -/
def lineBraceDelta (line : String) : Int := Id.run do
  let mut depth : Int := 0
  let mut inString := false
  let mut escape := false
  for c in line.toList do
    if escape then escape := false
    else if inString then
      if c == '\\' then escape := true
      else if c == '"' then inString := false
    else if c == '"' then inString := true
    else if c == '{' then depth := depth + 1
    else if c == '}' then depth := depth - 1
  return depth

/-! ## Scalars -/

inductive Scalar where
  | str (value : String)
  | bool (value : Bool)
  | long (value : Int)
  /-- A decimal written as Java prints a double. -/
  | double (text : String)

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

/-- The text of a string literal the way EDN reads it, or none when EDN would refuse an escape. -/
private def unescapeEdn (inner : List Char) : Option String := Id.run do
  let mut out := ""
  let mut rest := inner
  while true do
    match rest with
    | [] => return some out
    | '\\' :: e :: tail =>
        match e with
        | 't' => out := out.push '\t'; rest := tail
        | 'r' => out := out.push '\r'; rest := tail
        | 'n' => out := out.push '\n'; rest := tail
        | 'b' => out := out.push (Char.ofNat 8); rest := tail
        | 'f' => out := out.push (Char.ofNat 12); rest := tail
        | '\\' => out := out.push '\\'; rest := tail
        | '"' => out := out.push '"'; rest := tail
        | 'u' =>
            match tail with
            | a :: b :: c :: d :: tail' =>
                let hex (x : Char) : Option Nat :=
                  if x.isDigit then some (x.toNat - 48)
                  else if 'a' ≤ x && x ≤ 'f' then some (x.toNat - 87)
                  else if 'A' ≤ x && x ≤ 'F' then some (x.toNat - 55) else none
                match hex a, hex b, hex c, hex d with
                | some w, some x, some y, some z =>
                    out := out.push (Char.ofNat (((w * 16 + x) * 16 + y) * 16 + z)); rest := tail'
                | _, _, _, _ => return none
            | _ => return none
        | _ => return none
    | '\\' :: [] => return none
    | c :: tail => out := out.push c; rest := tail
  return none

/-- Is the whole text one double-quoted literal (`"(\\.|[^"])*"`)? -/
private def quotedLiteral (t : String) : Option (List Char) :=
  match t.toList with
  | '"' :: rest =>
      let rec go : List Char → List Char → Option (List Char)
        | acc, ['"'] => some acc.reverse
        | acc, '\\' :: c :: tail => go (c :: '\\' :: acc) tail
        | _, '"' :: _ => none
        | acc, c :: tail => go (c :: acc) tail
        | _, [] => none
      go [] rest
  | _ => none

private def isInteger (t : String) : Bool :=
  let body := if t.startsWith "-" then String.ofList t.toList.tail! else t
  !body.isEmpty && body.all Char.isDigit

private def isDecimal (t : String) : Bool :=
  let body := if t.startsWith "-" then String.ofList t.toList.tail! else t
  match body.splitOn "." with
  | [w, f] => !w.isEmpty && !f.isEmpty && w.all Char.isDigit && f.all Char.isDigit
  | _ => false

/-- The value an attribute's right-hand side reads as. -/
def parseScalar (raw : String) : Scalar :=
  let trimmed := trimText raw
  let t := if trimmed.endsWith "," then trimText (String.ofList trimmed.toList.dropLast) else trimmed
  -- `,\s*$` removes one trailing comma and the space around it
  if blank t then .str ""
  else
    match quotedLiteral t with
    | some inner =>
        match unescapeEdn inner with
        | some text => .str text
        | none => .str (String.ofList inner)
    | none =>
        if t.toLower == "true" then .bool true
        else if t.toLower == "false" then .bool false
        else if isInteger t then .long (t.toInt?.getD 0)
        else if isDecimal t then .double (javaDouble t)
        else .str t

/-- `clojure.core/pr-str` of a scalar, or the string itself. -/
def rawString : Scalar → String
  | .str s => s
  | .bool b => toString b
  | .long n => toString n
  | .double t => t

/-- The rendered form a scalar takes inside a ZIL attribute: a quoted string with `\` and `"` escaped. -/
def renderString (s : String) : String :=
  "\"" ++ (s.replace "\\" "\\\\").replace "\"" "\\\"" ++ "\""

/-! ## Blocks -/

/-- Simple top-level `key = value` assignments of a block body; nested objects and lists are skipped. -/
def parseTopLevelAttrs (body : String) : Array (String × Scalar) := Id.run do
  let mut depth : Int := 0
  let mut out : Array (String × Scalar) := #[]
  for line in splitLines body do
    let clean := trimText (stripInlineComment line)
    if depth == 0 && !blank clean then
      -- ([A-Za-z0-9_-]+)\s*=\s*(.+)
      let chars := clean.toList
      let key := chars.takeWhile isIdentChar
      let afterKey := chars.drop key.length
      let afterWs := afterKey.dropWhile Char.isWhitespace
      if !key.isEmpty then
        match afterWs with
        | '=' :: valueChars =>
            let value := trimText (String.ofList (valueChars.dropWhile Char.isWhitespace))
            if !value.isEmpty && value != "{" && !value.endsWith "{" then
              let k := String.ofList key
              out := match out.findIdx? (·.1 == k) with
                | some i => out.set! i (k, parseScalar value)
                | none => out.push (k, parseScalar value)
        | _ => pure ()
    depth := depth + lineBraceDelta clean
  return out

private def lastNonblankLine (s : String) : String :=
  let lines := (splitLines s).map (fun l => trimText (stripInlineComment l)) |>.filter (!blank ·)
  lines.getLast?.getD ""

structure Block where
  header : String
  body : String

/-- Top-level blocks of a file by brace matching: the last non-blank line before `{` is the header. -/
def extractTopLevelBlocks (text : String) : Array Block := Id.run do
  let chars := text.toList.toArray
  let mut out : Array Block := #[]
  let mut depth := 0
  let mut inString := false
  let mut escape := false
  let mut segmentStart := 0
  let mut blockOpen : Option Nat := none
  let mut blockHeader : Option String := none
  let slice (a b : Nat) : String := String.ofList ((chars.extract a b).toList)
  for i in [0:chars.size] do
    let c := chars[i]!
    if escape then escape := false
    else if inString then
      if c == '\\' then escape := true
      else if c == '"' then inString := false
    else if c == '"' then inString := true
    else if c == '{' then
      if depth == 0 then
        blockHeader := some (lastNonblankLine (slice segmentStart i))
        blockOpen := some i
        depth := 1
      else depth := depth + 1
    else if c == '}' then
      let next := depth - 1
      if next == 0 && blockOpen.isSome then
        let bodyStart := blockOpen.get! + 1
        let header := blockHeader.getD ""
        unless blank header do out := out.push { header, body := slice bodyStart i }
        depth := 0
        segmentStart := i + 1
        blockOpen := none
        blockHeader := none
      else depth := next
  return out

inductive Kind where
  | terraform
  | requiredProviders
  | provider (name : String)
  | resource (type name : String)
  | data (type name : String)
  | module (name : String)
  | variable (name : String)
  | output (name : String)

/-- Words and quoted strings of a header such as `resource "aws_instance" "web"`. -/
partial def parseHeader (header : String) : Option Kind :=
  let h := trimText header
  let lower := h.toLower
  if lower == "terraform" then some .terraform
  else if lower == "required_providers" then some .requiredProviders
  else
    let chars := h.toList
    let keyword := String.ofList (chars.takeWhile fun c => c.isAlpha || c == '_')
    let rec strings (cs : List Char) (acc : Array String) : Option (Array String) :=
      let cs' := cs.dropWhile Char.isWhitespace
      if cs.isEmpty then some acc
      else if cs'.length == cs.length then none   -- strings must be separated by whitespace
      else match cs' with
        | '"' :: rest =>
            let inner := rest.takeWhile (· ≠ '"')
            match rest.drop inner.length with
            | '"' :: tail => if inner.isEmpty then none else strings tail (acc.push (String.ofList inner))
            | _ => none
        | _ => none
    match strings (chars.drop keyword.length) #[] with
    | none => none
    | some parts =>
        match keyword.toLower, parts.size with
        | "provider", 1 => some (.provider parts[0]!)
        | "resource", 2 => some (.resource parts[0]! parts[1]!)
        | "data", 2 => some (.data parts[0]! parts[1]!)
        | "module", 1 => some (.module parts[0]!)
        | "variable", 1 => some (.variable parts[0]!)
        | "output", 1 => some (.output parts[0]!)
        | _, _ => none

/-- The providers a `required_providers` body names, with their `source` and `version` attributes. -/
def parseRequiredProviderMap (body : String) : Array (String × Array (String × Scalar)) := Id.run do
  let chars := body.toList.toArray
  let mut out := #[]
  let mut i := 0
  while i < chars.size do
    if isIdentChar chars[i]! && (i == 0 || !isIdentChar chars[i - 1]!) then
      let mut j := i
      while j < chars.size && isIdentChar chars[j]! do j := j + 1
      let name := String.ofList (chars.extract i j).toList
      let mut k := j
      while k < chars.size && chars[k]!.isWhitespace do k := k + 1
      if chars[k]? == some '=' then
        k := k + 1
        while k < chars.size && chars[k]!.isWhitespace do k := k + 1
        if chars[k]? == some '{' then
          let start := k + 1
          let mut e := start
          while e < chars.size && chars[e]! != '}' do e := e + 1
          if e < chars.size then
            out := out.push (name, parseTopLevelAttrs (String.ofList (chars.extract start e).toList))
            i := e + 1
            continue
      i := j
    else i := i + 1
  return out

def parseRequiredProviders (terraformBody : String) : Array (String × Array (String × Scalar)) := Id.run do
  let mut merged : Array (String × Array (String × Scalar)) := #[]
  for block in extractTopLevelBlocks terraformBody do
    if let some .requiredProviders := parseHeader block.header then
      for (name, attrs) in parseRequiredProviderMap block.body do
        merged := match merged.findIdx? (·.1 == name) with
          | some i => merged.set! i (name, attrs)
          | none => merged.push (name, attrs)
  return merged

/-! ## Rendering -/

def safeIdent (text : String) : String :=
  String.ofList (text.toList.map fun c => if c.isAlphanum || c == '_' || c == '.' || c == ':' || c == '-' then c else '_')

private def lookup (attrs : Array (String × Scalar)) (key : String) : Option Scalar :=
  attrs.find? (·.1 == key) |>.map (·.2)

private def firstPart (text sep : String) : String :=
  trimText ((text.splitOn sep).head!)

private def inferProviderFromType (t : String) : Option String :=
  let p := firstPart t "_"
  if p.isEmpty then none else some p

private def providerLocalFromAttrs (attrs : Array (String × Scalar)) : Option String :=
  (lookup attrs "provider").bind fun v =>
    let p := firstPart (rawString v) "."
    if p.isEmpty then none else some p

private def fileEntity (path : String) : String :=
  let name := (System.FilePath.mk path).fileName.getD path
  let rec squash : List Char → Bool → List Char
    | [], _ => []
    | c :: cs, prevBad => if c.isAlphanum then c :: squash cs false else if prevBad then squash cs true else '_' :: squash cs true
  "hcl:file:" ++ String.ofList (squash name.toList false)

private def renderAttrFacts (obj : String) (attrs : Array (String × Scalar)) : Array String :=
  (attrs.qsort fun a b => compareKeys a.1 b.1 == .lt).map fun (k, v) =>
    s!"{obj}#attr@value:present [key=value:{safeIdent k}, raw={renderString (rawString v)}]."

structure Parsed where
  requiredProviders : Array (String × Array (String × Scalar)) := #[]
  providerConfigs : Array (String × Array (String × Scalar) × String) := #[]
  resources : Array (String × String × Array (String × Scalar) × String) := #[]
  data : Array (String × String × Array (String × Scalar) × String) := #[]
  modules : Array (String × Array (String × Scalar) × String) := #[]
  variables : Array (String × Array (String × Scalar) × String) := #[]
  outputs : Array (String × Array (String × Scalar) × String) := #[]

structure Report where
  text : String
  files : Array String
  providers : Nat
  resources : Nat
  data : Nat
  modules : Nat
  variables : Nat
  outputs : Nat

/-- `.tf` and `.hcl` files of a file or directory, sorted by path. -/
partial def collectFiles (path : System.FilePath) : IO (Array String) := do
  let isHcl (p : System.FilePath) := p.toString.endsWith ".tf" || p.toString.endsWith ".hcl"
  if !(← path.pathExists) then return #[]
  if ← path.isDir then
    let rec walk (dir : System.FilePath) : IO (Array String) := do
      let mut out := #[]
      for entry in ← dir.readDir do
        if ← entry.path.isDir then out := out ++ (← walk entry.path)
        else if isHcl entry.path then out := out.push entry.path.toString
      return out
    return (← walk path).qsort fun a b => compareKeys a b == .lt
  else return if isHcl path then #[path.toString] else #[]

/-- Import HCL text from the given files into ZIL source. -/
def importFiles (files : Array String) (moduleName : String := "hcl.import") : IO Report := do
  if files.isEmpty then throw (IO.userError "No .tf/.hcl files found for import")
  let mut parsed : Parsed := {}
  for file in files do
    let text ← IO.FS.readFile file
    let entity := fileEntity file
    for block in extractTopLevelBlocks text do
      match parseHeader block.header with
      | some .terraform =>
          for (name, attrs) in parseRequiredProviders block.body do
            parsed := { parsed with requiredProviders :=
              match parsed.requiredProviders.findIdx? (·.1 == name) with
              | some i => parsed.requiredProviders.set! i (name, attrs)
              | none => parsed.requiredProviders.push (name, attrs) }
      | some (.provider provider) =>
          parsed := { parsed with providerConfigs := parsed.providerConfigs.push (provider, parseTopLevelAttrs block.body, entity) }
      | some (.resource t n) =>
          parsed := { parsed with resources := parsed.resources.push (t, n, parseTopLevelAttrs block.body, entity) }
      | some (.data t n) =>
          parsed := { parsed with data := parsed.data.push (t, n, parseTopLevelAttrs block.body, entity) }
      | some (.module n) =>
          parsed := { parsed with modules := parsed.modules.push (n, parseTopLevelAttrs block.body, entity) }
      | some (.variable n) =>
          parsed := { parsed with variables := parsed.variables.push (n, parseTopLevelAttrs block.body, entity) }
      | some (.output n) =>
          parsed := { parsed with outputs := parsed.outputs.push (n, parseTopLevelAttrs block.body, entity) }
      | _ => pure ()
  -- providers named anywhere, sorted and distinct
  let mut locals : Array String := #[]
  for (name, _) in parsed.requiredProviders do locals := locals.push name
  for (provider, _, _) in parsed.providerConfigs do locals := locals.push provider
  for (t, _, attrs, _) in parsed.resources do
    if let some p := (providerLocalFromAttrs attrs).orElse fun _ => inferProviderFromType t then locals := locals.push p
  for (t, _, attrs, _) in parsed.data do
    if let some p := (providerLocalFromAttrs attrs).orElse fun _ => inferProviderFromType t then locals := locals.push p
  let providerLocals := ((locals.filter (!blank ·)).map safeIdent).toList.eraseDups.toArray.qsort fun a b => compareKeys a b == .lt
  let source (local_ : String) : String :=
    match (parsed.requiredProviders.find? (·.1 == local_)).bind (fun (_, attrs) => lookup attrs "source") with
    | some v => if blank (rawString v) then "hashicorp/" ++ local_ else rawString v
    | none => "hashicorp/" ++ local_
  let version (local_ : String) : Option String :=
    ((parsed.requiredProviders.find? (·.1 == local_)).bind fun (_, attrs) => lookup attrs "version").bind fun v =>
      let s := rawString v
      if s.isEmpty then none else some s
  let providerLines := providerLocals.map fun local_ =>
    let pairs := #[s!"source={renderString (source local_)}"] ++
      (match version local_ with | some v => #[s!"version={renderString v}"] | none => #[]) ++ #["language=hcl", "engine=opentofu"]
    s!"PROVIDER {local_} [{", ".intercalate pairs.toList}]."
  let mut providerConfigLines : Array String := #[]
  for (provider, attrs, file) in parsed.providerConfigs do
    let obj := "provider:" ++ safeIdent provider
    providerConfigLines := providerConfigLines.push s!"{obj}#configured_in@{file}." ++ renderAttrFacts obj attrs
  let mut resourceLines : Array String := #[]
  for (t, n, attrs, file) in parsed.resources do
    let obj := s!"hcl_resource:{safeIdent t}:{safeIdent n}"
    resourceLines := resourceLines ++ #[s!"{obj}#kind@entity:hcl_resource.", s!"{obj}#resource_type@value:{safeIdent t}.",
      s!"{obj}#resource_name@value:{safeIdent n}.", s!"{obj}#declared_in@{file}."]
    if let some p := (providerLocalFromAttrs attrs).orElse fun _ => inferProviderFromType t then
      resourceLines := resourceLines.push s!"{obj}#provider@provider:{safeIdent p}."
    resourceLines := resourceLines ++ renderAttrFacts obj attrs
  let mut dataLines : Array String := #[]
  for (t, n, attrs, file) in parsed.data do
    let obj := s!"hcl_data:{safeIdent t}:{safeIdent n}"
    dataLines := dataLines ++ #[s!"{obj}#kind@entity:hcl_data.", s!"{obj}#data_type@value:{safeIdent t}.",
      s!"{obj}#data_name@value:{safeIdent n}.", s!"{obj}#declared_in@{file}."]
    if let some p := (providerLocalFromAttrs attrs).orElse fun _ => inferProviderFromType t then
      dataLines := dataLines.push s!"{obj}#provider@provider:{safeIdent p}."
    dataLines := dataLines ++ renderAttrFacts obj attrs
  let simple (prefix_ kind nameRel : String) (items : Array (String × Array (String × Scalar) × String)) : Array String :=
    items.foldl (fun acc (n, attrs, file) =>
      let obj := s!"{prefix_}:{safeIdent n}"
      acc ++ #[s!"{obj}#kind@entity:{kind}.", s!"{obj}#{nameRel}@value:{safeIdent n}.", s!"{obj}#declared_in@{file}."] ++
        renderAttrFacts obj attrs) #[]
  let lines : Array String :=
    #[s!"MODULE {moduleName}.", ""] ++ providerLines ++ #[""] ++ providerConfigLines ++ resourceLines ++ dataLines ++
    simple "hcl_module" "hcl_module" "module_name" parsed.modules ++
    simple "hcl_variable" "hcl_variable" "variable_name" parsed.variables ++
    simple "hcl_output" "hcl_output" "output_name" parsed.outputs
  return { text := "\n".intercalate lines.toList ++ "\n", files, providers := providerLocals.size,
           resources := parsed.resources.size, data := parsed.data.size, modules := parsed.modules.size,
           variables := parsed.variables.size, outputs := parsed.outputs.size }

/-- Import a file or directory. -/
def importPath (path : System.FilePath) (moduleName : String := "hcl.import") : IO Report := do
  importFiles (← collectFiles path) moduleName

end Zil.Import.Hcl
