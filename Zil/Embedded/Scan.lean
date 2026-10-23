import Zil.Crypto.Sha256
import Zil.Json.Ordered
import Zil.Util.JavaText
import Zil.Parser.MacroProgram

/-!
# Embedded ZIL blocks

Read-only extraction of explicitly delimited ZIL comment blocks from host-language sources:

    @zil [target=self|<target>]
    <ground facts or `USE` macro calls, one per line, behind any comment prefix>
    @endzil

`target=self` (the default) attaches the block to the first host declaration after it. The statements may name the
block's own context with the words `self`, `file`, `module`, `namespace`, `project`, `revision`, `declaration_kind` and
`source_span`. A scan renders the blocks as ZIL facts, writes a versioned snapshot, and compares a snapshot with the
sources as they are now (drift).

The earlier Clojure implementation of this scan wrote the facts and the JSON snapshot that this module writes; the
tests compare the two byte for byte.
-/

namespace Zil.Embedded

open Zil.Json Zil.JavaText

structure ScanError where
  message : String
  data : Array (String × J) := #[]

abbrev ScanM := ExceptT ScanError IO

private def fail {α : Type} (message : String) (data : Array (String × J) := #[]) : Except ScanError α :=
  .error { message, data }

private def failM {α : Type} (message : String) (data : Array (String × J) := #[]) : ScanM α :=
  throw { message, data }

private def liftE {α : Type} (value : Except ScanError α) : ScanM α := ExceptT.mk (pure value)

/-! ## Java text rules the scan was defined with -/

private def startsWithList : List Char → List Char → Bool
  | _, [] => true
  | [], _ :: _ => false
  | a :: as, b :: bs => a == b && startsWithList as bs

/-- The characters after the first occurrence of `needle`. -/
private partial def after? (haystack needle : List Char) : Option (List Char) :=
  if startsWithList haystack needle then some (haystack.drop needle.length)
  else match haystack with
    | [] => none
    | _ :: rest => after? rest needle

private def contains (text needle : String) : Bool := (after? text.toList needle.toList).isSome

private def sha256Hex (text : String) : String := Zil.Crypto.Sha256.hex text.toUTF8

/-- `java.io.File` path text: repeated separators collapse and a trailing separator goes. -/
def normalizePath (path : String) : String :=
  let parts := (path.splitOn "/").filter (!·.isEmpty)
  let joined := "/".intercalate parts
  if path.startsWith "/" then "/" ++ joined else if joined.isEmpty then path else joined

/-- `java.io.File.getParent`. -/
def parentOf (path : String) : Option String :=
  let normal := normalizePath path
  if normal == "/" then none
  else match (normal.splitOn "/").reverse with
    | _ :: [] => none
    | _ :: rest =>
        let parent := "/".intercalate rest.reverse
        some (if parent.isEmpty then "/" else parent)
    | [] => none

/-- `java.io.File.getName`. -/
def fileName (path : String) : String :=
  let normal := normalizePath path
  if normal == "/" then "" else (normal.splitOn "/").getLast!

/-! ## Hosts -/

inductive Language where
  | lean4 | python | clojure | rust | markdown | unknown
  deriving BEq, Repr

def Language.name : Language → String
  | .lean4 => "lean4" | .python => "python" | .clojure => "clojure"
  | .rust => "rust" | .markdown => "markdown" | .unknown => "unknown"

/-- The text after the last dot of the whole path, lower-cased (the path need not have a file name). -/
def extensionOf (path : String) : Option String :=
  match path.splitOn "." with
  | [] | [_] => none
  | parts => let last := parts.getLast!; if last.isEmpty then none else some last.toLower

def languageOfExtension : String → Option Language
  | "lean" => some .lean4 | "py" => some .python | "clj" => some .clojure | "cljs" => some .clojure
  | "cljc" => some .clojure | "rs" => some .rust | "md" => some .markdown | _ => none

def languageFor (path : String) : Language :=
  (extensionOf path >>= languageOfExtension).getD .unknown

private def targetPrefix : Language → String
  | .lean4 => "lean:" | .python => "python:" | .clojure => "clojure:" | .rust => "rust:"
  | .markdown => "markdown:" | .unknown => "host:"

private def modulePrefix : Language → String
  | .lean4 => "lean_module:" | .python => "python_module:" | .clojure => "clojure_module:"
  | .rust => "rust_module:" | _ => "module:"

private def namespacePrefix : Language → String
  | .lean4 => "lean_namespace:" | .python => "python_namespace:" | .clojure => "clojure_namespace:"
  | .rust => "rust_namespace:" | _ => "namespace:"

private def isIdStart (c : Char) : Bool := (c.isAlpha && c.toNat < 128) || c == '_'
private def isIdChar (c : Char) : Bool := isIdStart c || (c.isDigit && c.toNat < 128)

/-- `[A-Za-z_][A-Za-z0-9_]*`, plus `'` and `.` when `dotted`. -/
private def identifier (chars : List Char) (dotted : Bool) : Option String :=
  match chars with
  | first :: rest =>
      if isIdStart first then
        some (String.ofList (first :: rest.takeWhile fun c => isIdChar c || (dotted && (c == '\'' || c == '.'))))
      else none
  | [] => none

private def dropSpace1 (chars : List Char) : Option (List Char) :=
  let rest := chars.dropWhile isReSpace
  if rest.length < chars.length then some rest else none

/-- A keyword in `words`, then whitespace, then an identifier: `(kind, name)`. -/
private def keywordAndName (chars : List Char) (words : List String) (dotted : Bool) : Option (String × String) :=
  let word := String.ofList (chars.takeWhile (!isReSpace ·))
  if words.contains word then
    (dropSpace1 (chars.drop word.length) >>= fun rest => identifier rest dotted).map (word.toLower, ·)
  else none

private def declarationMatch (language : Language) (line : String) : Option (String × String) :=
  let chars := line.toList.dropWhile isReSpace
  match language with
  | .lean4 =>
      keywordAndName chars ["theorem", "def", "opaque", "axiom", "inductive", "structure", "class", "abbrev"] true
  | .python =>
      let chars := if String.ofList (chars.takeWhile (!isReSpace ·)) == "async" then
          (dropSpace1 (chars.drop 5)).getD chars else chars
      keywordAndName chars ["def", "class"] false
  | .clojure =>
      match chars with
      | '(' :: rest =>
          let word := String.ofList (rest.takeWhile (!isReSpace ·))
          if ["defn", "defn-", "def", "defmacro"].contains word then
            (dropSpace1 (rest.drop word.length)).bind fun after =>
              let name := after.takeWhile fun c => !(isReSpace c || c == '[' || c == ']' || c == '(' || c == ')')
              if name.isEmpty then none else some (word.toLower, String.ofList name)
          else none
      | _ => none
  | .rust =>
      let afterPub : Option (List Char) :=
        if startsWithList chars ['p', 'u', 'b'] then
          let rest := chars.drop 3
          let rest := match rest with
            | '(' :: tail => match tail.dropWhile (· != ')') with | ')' :: after => after | _ => rest
            | _ => rest
          dropSpace1 rest
        else some chars
      afterPub.bind fun chars =>
        let chars := if String.ofList (chars.takeWhile (!isReSpace ·)) == "async" then
            (dropSpace1 (chars.drop 5)).getD chars else chars
        keywordAndName chars ["fn", "struct", "enum", "trait"] false
  | _ => none

/-- Remove one comment opener from the start of a line and a comment closer from its end. -/
def stripCommentPrefix (line : String) : String :=
  let chars := (jtrim line).toList
  let rest : List Char :=
    match chars with
    | '/' :: '*' :: tail => tail.dropWhile (· == '*')
    | '*' :: _ =>
        let stars := chars.dropWhile (· == '*')
        match stars with
        | '/' :: tail => tail
        | _ => chars.drop 1
    | '/' :: '/' :: tail => tail.dropWhile (· == '/')
    | ';' :: ';' :: tail => tail.dropWhile (· == ';')
    | '#' :: tail => tail.dropWhile (· == '#')
    | _ => chars
  let rest := rest.dropWhile isReSpace
  let text := String.ofList rest
  let text := if text.endsWith "*/" then String.ofList ((text.toList.dropLast.dropLast.reverse.dropWhile isReSpace).reverse)
    else String.ofList ((rest.reverse.dropWhile isReSpace).reverse)
  jtrim text

/-- `@zil` or `@zil target=<target>` anywhere in a line: the requested target, `self` by default. -/
def markerTarget (line : String) : Option String :=
  (after? line.toList "@zil".toList).map fun rest =>
    match dropSpace1 rest with
    | some ('t' :: 'a' :: 'r' :: 'g' :: 'e' :: 't' :: tail) =>
        match tail.dropWhile isReSpace with
        | '=' :: value =>
            let word := (value.dropWhile isReSpace).takeWhile (!isReSpace ·)
            if word.isEmpty then "self" else String.ofList word
        | _ => "self"
    | _ => "self"

private def leanNamespaceAt (lines : Array String) (markerIndex : Nat) : Array String := Id.run do
  let mut stack : Array String := #[]
  let nameLine (word : String) (line : String) : Option String :=
    let chars := line.toList.dropWhile isReSpace
    if startsWithList chars word.toList then
      (dropSpace1 (chars.drop word.length)).bind fun rest =>
        (identifier rest true).bind fun name =>
          if (rest.drop name.length).all isReSpace then some name else none
    else none
  for line in lines.extract 0 markerIndex do
    match nameLine "namespace" line with
    | some name => stack := stack.push name
    | none =>
        match nameLine "end" line with
        | some ended => if stack.back? == some ended then stack := stack.pop
        | none => pure ()
  return stack

private def resolveSelf (lines : Array String) (language : Language) (afterLine : Nat) (explicit : String)
    (namespaces : Array String) : Except ScanError (String × Option String) :=
  let declaration := (lines.extract afterLine lines.size).findSome? (declarationMatch language)
  if explicit != "self" then pure (explicit, declaration.map (·.1))
  else match declaration with
    | none => fail "Embedded ZIL target=self has no following host declaration"
        #[("code", .str "attachment"), ("language", .str language.name), ("after_line", .int afterLine)]
    | some (kind, name) =>
        let qualified :=
          if language != .lean4 || contains name "." || namespaces.isEmpty then name
          else ".".intercalate namespaces.toList ++ "." ++ name
        pure (targetPrefix language ++ qualified, some kind)

/-- A statement must be one ground fact, `subject#attribute@object.`, with `self` standing for the block's target. -/
private def canonicalStatement (statement target : String) : Except ScanError String := do
  let line := jtrim statement
  unless line.endsWith "." do
    fail "Embedded ZIL statements must end with '.'" #[("code", .str "syntax"), ("statement", .str statement)]
  let body := line.dropEnd 1 |>.toString
  let chars := body.toList
  let subject := chars.takeWhile fun c => c != '#' && !isReSpace c
  let ok :=
    !subject.isEmpty && (match chars.drop subject.length with
      | '#' :: rest =>
          (match identifier rest false with
            | some attr =>
                (match rest.drop attr.length with
                  | '@' :: object => !object.isEmpty && object.all (!isReSpace ·)
                  | _ => false)
            | none => false)
      | _ => false)
  unless ok do
    fail "Initial embedded scanner accepts canonical ground facts only"
      #[("code", .str "syntax"), ("statement", .str statement)]
  let replaced := if startsWithList chars "self#".toList then target ++ (body.drop 4).toString else body
  pure (replaced ++ ".")

private def isBoundary (c : Char) : Bool :=
  (c.isAlpha && c.toNat < 128) || (c.isDigit && c.toNat < 128) || c == '_' || c == '.' || c == ':' || c == '-'

/-- Replace each whole-word `key` (not next to a letter, digit, `_`, `.`, `:` or `-`) with `value`. -/
private def replaceWord (text key value : String) : String := Id.run do
  let chars := text.toList.toArray
  let keyChars := key.toList.toArray
  let mut out := ""
  let mut i := 0
  while i < chars.size do
    let here := i + keyChars.size ≤ chars.size && (List.range keyChars.size).all fun j => chars[i + j]! == keyChars[j]!
    if here && (i == 0 || !isBoundary chars[i - 1]!) && (i + keyChars.size == chars.size || !isBoundary chars[i + keyChars.size]!) then
      out := out ++ value
      i := i + keyChars.size
    else
      out := out.push chars[i]!
      i := i + 1
  return out

private def moduleNameFor (path : String) (language : Language) : String :=
  let slashed := path.replace "\\" "/"
  let parts := slashed.splitOn "."
  let base := if parts.length ≥ 2 && !parts.getLast!.isEmpty then ".".intercalate parts.dropLast else slashed
  let dotted := Id.run do
    let mut out := ""
    let mut previousSlash := false
    for c in base.toList do
      if c == '/' then
        unless previousSlash do out := out.push '.'
        previousSlash := true
      else
        out := out.push c
        previousSlash := false
    return out
  modulePrefix language ++ (if dotted.startsWith "." then (dotted.drop 1).toString else dotted)

/-- `java.lang.String.split` with a single dot: trailing empty pieces are dropped. -/
private def splitDots (text : String) : List String :=
  let pieces := text.splitOn "."
  (pieces.reverse.dropWhile String.isEmpty).reverse

private def namespaceFor (target : String) (language : Language) : String :=
  let plain := (target.drop (targetPrefix language).length).toString
  let pieces := splitDots plain
  namespacePrefix language ++ (if pieces.length > 1 then ".".intercalate pieces.dropLast else "root")

/-! ## Scanning -/

structure Block where
  blockId : String
  target : String
  startLine : Nat
  endLine : Nat
  sourceHash : String
  macroRevision : String
  moduleName : String
  nameSpace : String
  project : String
  sourceSpan : String
  statements : Array String
  declarationKind : Option String := none

/-- The block as a snapshot entry, with the key order of the earlier implementation (a Clojure hash map). -/
def Block.toJson (block : Block) (hostPath : Option (String × String) := none) : J :=
  let fields : Array (String × Option J) := #[
    ("path", hostPath.map (.str ·.1)),
    ("macro_revision", some (.str block.macroRevision)),
    ("start_line", some (.int block.startLine)),
    ("source_hash", some (.str block.sourceHash)),
    ("block_id", some (.str block.blockId)),
    ("declaration_kind", block.declarationKind.map .str),
    ("module", some (.str block.moduleName)),
    ("project", some (.str block.project)),
    ("language", hostPath.map (.str ·.2)),
    ("trust", some (.str "asserted_annotation")),
    ("target", some (.str block.target)),
    ("source_span", some (.str block.sourceSpan)),
    ("namespace", some (.str block.nameSpace)),
    ("end_line", some (.int block.endLine)),
    ("statements", some (.arr (block.statements.map .str)))]
  .obj (fields.filterMap fun (key, value) => value.map (key, ·))

structure Report where
  path : String
  language : Language
  sourceHash : String
  blocks : Array Block

private def macroEnvironment (macroText : String) : Except ScanError (Array Zil.MacroDef) :=
  if macroText.toList.all isJavaWs then pure #[]
  else (Zil.Parser.Macro.collectMacros macroText).mapError fun e => { message := e.message, data := #[("code", .str "macro")] }

/-- Extract the blocks of one host source; `self` attaches a block to the first declaration after it. -/
def scanText (path text : String) (macroText : String := "") (project : Option String := none) :
    Except ScanError Report := do
  let lines := splitLines text
  let language := languageFor path
  let sourceHash := "sha256:" ++ sha256Hex text
  let macroRevision := "sha256:" ++ sha256Hex macroText
  let macros ← macroEnvironment macroText
  let projectName := project.getD (fileName ((parentOf path).getD "."))
  let mut index := 0
  let mut ordinal := 0
  let mut blocks : Array Block := #[]
  while index < lines.size do
    match markerTarget lines[index]! with
    | none => index := index + 1
    | some requested =>
        let endIndex := (List.range' (index + 1) (lines.size - (index + 1))).find? fun j => contains lines[j]! "@endzil"
        let some endIndex := endIndex
          | fail "Embedded @zil block has no @endzil marker"
              #[("code", .str "syntax"), ("path", .str path), ("start_line", .int (index + 1))]
        let namespaces := if language == .lean4 then leanNamespaceAt lines index else #[]
        let (target, declarationKind) ← resolveSelf lines language (endIndex + 1) requested namespaces
        let moduleName := moduleNameFor path language
        let nameSpace := namespaceFor target language
        let sourceSpan := s!"source_span:{path}:{index + 1}-{endIndex + 1}"
        let context : Array (String × String) := #[
          ("self", target), ("file", "file:" ++ path), ("module", moduleName), ("namespace", nameSpace),
          ("project", "project:" ++ projectName), ("revision", sourceHash),
          ("declaration_kind", language.name ++ "_kind:" ++ declarationKind.getD "unknown"),
          ("source_span", sourceSpan)]
        let raw := (lines.extract (index + 1) endIndex).map stripCommentPrefix |>.filter (!·.isEmpty)
        let substituted := raw.map fun statement => context.foldl (fun current (key, value) => replaceWord current key value) statement
        let expanded ← (Zil.Parser.Macro.expandStatements macros substituted).mapError fun e =>
          { message := e.message, data := #[("code", .str "macro")] }
        let statements ← expanded.mapM (canonicalStatement · target)
        let blockId := "embedded:" ++ ((sha256Hex s!"{path}:{ordinal}").take 16).toString
        if statements.isEmpty then
          fail "Embedded @zil block is empty"
            #[("code", .str "syntax"), ("path", .str path), ("start_line", .int (index + 1))]
        blocks := blocks.push {
          blockId, target, startLine := index + 1, endLine := endIndex + 1, sourceHash, macroRevision,
          moduleName, nameSpace, project := "project:" ++ projectName, sourceSpan, statements, declarationKind }
        index := endIndex + 1
        ordinal := ordinal + 1
  pure { path, language, sourceHash, blocks }

/-! ## Facts -/

def renderZil (reports : Array Report) (moduleName : String) : String :=
  let facts := reports.foldl (init := (#[] : Array String)) fun facts report =>
    report.blocks.foldl (init := facts) fun facts block =>
      let id := prString block.blockId
      facts ++ #[
        s!"{id}#kind@{prString "embedded_zil_block"}.",
        s!"{id}#target@{prString block.target}.",
        s!"{id}#trust@{prString "trust:asserted_annotation"}.",
        s!"{id}#source_hash@{prString block.sourceHash}.",
        s!"{id}#macro_revision@{prString block.macroRevision}.",
        s!"{id}#start_line@{prString (toString block.startLine)}.",
        s!"{id}#end_line@{prString (toString block.endLine)}."] ++ block.statements
  s!"MODULE {moduleName}.\n\n// Generated read-only from explicit @zil/@endzil source annotations.\n" ++
    "\n".intercalate facts.toList ++ (if facts.isEmpty then "" else "\n")

/-! ## Files -/

private def absolutePath (path : String) : IO String := do
  if path.startsWith "/" then pure (normalizePath path)
  else pure (normalizePath ((← IO.currentDir).toString ++ "/" ++ path))

private def isDirectory (path : String) : IO Bool := do
  match ← (System.FilePath.mk path).metadata.toBaseIO with
  | .ok metadata => pure (metadata.type == .dir)
  | .error _ => pure false

private def isFile (path : String) : IO Bool := do
  match ← (System.FilePath.mk path).metadata.toBaseIO with
  | .ok metadata => pure (metadata.type == .file)
  | .error _ => pure false

private def byName (names : Array String) : Array String := names.qsort fun a b => compareKeys a b == .lt

private partial def walk (dir : String) : IO (Array String) := do
  let mut out : Array String := #[]
  for entry in ← (System.FilePath.mk dir).readDir do
    let child := (if dir == "/" then "" else dir) ++ "/" ++ entry.fileName
    if ← isDirectory child then out := out ++ (← walk child)
    else if ← isFile child then out := out.push child
  return out

/-- The host sources under `path`: the file itself, or the supported files below a directory, sorted. -/
def sourceFiles (path : String) : ScanM (Array String) := do
  let normal := normalizePath path
  if ← isFile normal then pure #[normal]
  else if ← isDirectory normal then
    pure (byName ((← walk normal).filter fun file => (extensionOf file >>= languageOfExtension).isSome))
  else failM "Embedded scan path does not exist" #[("code", .str "io"), ("path", .str path)]

/-- The `.zc` files of an explicit library directory, or of the nearest `lib/` above the source, sorted by name. -/
def libraryFiles (source : String) (libDir : Option String) : IO (Array String) := do
  let resolved ← match libDir with
    | some dir => pure (some dir)
    | none => do
        let mut current := parentOf (← absolutePath source)
        let mut found : Option String := none
        while found.isNone && current.isSome do
          let candidate := (if current == some "/" then "" else current.get!) ++ "/lib"
          if ← isDirectory candidate then found := some candidate
          current := current.bind parentOf
        pure found
  match resolved with
  | none => pure #[]
  | some dir =>
      if !(← isDirectory dir) then pure #[]
      else
        let names := (← (System.FilePath.mk dir).readDir).map (·.fileName) |>.filter (·.endsWith ".zc")
        let mut files : Array String := #[]
        for name in byName names do
          let file := (if dir == "/" then "" else dir) ++ "/" ++ name
          if ← isFile file then files := files.push file
        pure files

private def macroTextFor (source : String) (libDir : Option String) : IO String := do
  let texts ← (← libraryFiles source libDir).mapM fun file => IO.FS.readFile (System.FilePath.mk file)
  pure ("\n".intercalate texts.toList)

structure ScanResult where
  path : String
  moduleName : String
  reports : Array Report
  text : String

def ScanResult.blockCount (result : ScanResult) : Nat := result.reports.foldl (· + ·.blocks.size) 0

/-- Scan a file or a directory; the facts must parse as ZIL. -/
def scanPath (path : String) (moduleName : String := "embedded.annotations") (outputPath : Option String := none)
    (libDir : Option String := none) : ScanM ScanResult := do
  let project := fileName path
  let mut reports : Array Report := #[]
  for file in ← sourceFiles path do
    let text ← IO.FS.readFile file
    reports := reports.push (← liftE (scanText file text (← macroTextFor file libDir) (some project)))
  let text := renderZil reports moduleName
  match Zil.Parser.MacroProgram.parseText text with
  | .ok _ => pure ()
  | .error error => failM error.message #[("code", .str "compile")]
  if let some out := outputPath then
    if let some parent := (System.FilePath.mk out).parent then IO.FS.createDirAll parent
    IO.FS.writeFile out text
  pure { path, moduleName, reports, text }

/-! ## Snapshots and drift -/

def snapshotFormat : String := "zil.embedded-snapshot.v0.1"

/-- The baseline of a scan: its blocks, by block id, each with its host path and language. -/
def snapshotData (scan : ScanResult) : J :=
  let blocks := scan.reports.foldl (init := (#[] : Array (String × J))) fun acc report =>
    report.blocks.foldl (init := acc) fun acc block =>
      acc.push (block.blockId, block.toJson (some (report.path, report.language.name)))
  let sorted := blocks.qsort fun a b => compareKeys a.1 b.1 == .lt
  .obj #[("format", .str snapshotFormat), ("root", .str scan.path), ("module", .str scan.moduleName),
    ("blocks", .arr (sorted.map (·.2)))]

def writeSnapshot (scan : ScanResult) (outputPath : String) : IO J := do
  let snapshot := snapshotData scan
  if let some parent := (System.FilePath.mk outputPath).parent then IO.FS.createDirAll parent
  IO.FS.writeFile outputPath (write snapshot (escapeSlash := false) ++ "\n")
  pure snapshot

def readSnapshot (path : String) : ScanM J := do
  let text ← IO.FS.readFile path
  match parse text with
  | .error message => failM s!"Unsupported embedded snapshot: {message}" #[("code", .str "validation")]
  | .ok snapshot =>
      if snapshot.getStr? "format" != some snapshotFormat then
        failM "Unsupported embedded snapshot format"
          #[("code", .str "validation"), ("format", (snapshot.get? "format").getD .null)]
      else pure snapshot

private def driftFields : List (String × String) :=
  [("source_hash", "source_changed"), ("macro_revision", "macro_changed"),
   ("target", "target_changed"), ("statements", "expansion_changed")]

private def blocksById (snapshot : J) : Array (String × J) :=
  let blocks := (snapshot.get? "blocks" >>= J.asArr?).getD #[]
  blocks.filterMap fun block => (block.getStr? "block_id").map (·, block)

/-- Compare two snapshots by block id. -/
def driftBetween (baseline current : J) : J :=
  let before := blocksById baseline
  let after := blocksById current
  let ids (blocks : Array (String × J)) := (blocks.map (·.1)).qsort fun a b => compareKeys a b == .lt
  let beforeIds := ids before
  let afterIds := ids after
  let find (blocks : Array (String × J)) (id : String) : J := (blocks.find? (·.1 == id)).map (·.2) |>.getD .null
  let removed := (beforeIds.filter (!afterIds.contains ·)).map fun id =>
    J.obj #[("block_id", .str id), ("kind", .str "block_removed"), ("before", find before id)]
  let added := (afterIds.filter (!beforeIds.contains ·)).map fun id =>
    J.obj #[("block_id", .str id), ("kind", .str "block_added"), ("after", find after id)]
  let changed := (beforeIds.filter afterIds.contains).foldl (init := (#[] : Array J)) fun acc id =>
    driftFields.foldl (init := acc) fun acc (field, kind) =>
      let old := ((find before id).get? field).getD .null
      let new := ((find after id).get? field).getD .null
      if J.beq old new then acc
      else acc.push (.obj #[("block_id", .str id), ("kind", .str kind), ("field", .str field), ("before", old), ("after", new)])
  let differences := removed ++ added ++ changed
  .obj #[("ok", .bool differences.isEmpty), ("drift", .bool !differences.isEmpty),
    ("baseline_format", (baseline.get? "format").getD .null),
    ("block_count_before", .int before.size), ("block_count_after", .int after.size),
    ("differences", .arr differences)]

def driftCheck (sourcePath baselinePath : String) (libDir : Option String := none) : ScanM J := do
  let baseline ← readSnapshot baselinePath
  let scan ← scanPath sourcePath (libDir := libDir)
  pure (driftBetween baseline (snapshotData scan))

end Zil.Embedded
