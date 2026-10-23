import Zil.Embedded.Scan
import Zil.Parser.DeclarationProgram
import Zil.Process.Run

/-!
# Compiling embedded ZIL blocks

Every `@zil` block found under the chosen roots becomes its own ZIL module, which compiles to a Lean module under an
output root; each generated module is then typechecked with `lake env lean`. The result is a manifest
(`ZIL-EMBEDDED-MANIFEST/1`, JSON) that records what was found, what was written and what failed.

A host file that cannot be scanned is reported in the manifest and does not stop the other files; a block that does
not compile or typecheck fails only itself.
-/

namespace Zil.Embedded

open Zil.Json Zil.JavaText

structure Options where
  roots : Array String := #["."]
  outputRoot : String := "generated/embedded"
  manifest : String := "generated/embedded/manifest.json"
  namespacePrefix : String := "Zil.Embedded"
  libDir : Option String := none
  checkOnly : Bool := false
  requireBlocks : Bool := false
  verifyGenerated : Bool := true

/-! ## Paths -/

/-- An absolute, lexically normalised path with symbolic links resolved where the path exists. -/
def absolutePath (path : String) : IO String := do
  let cwd ← IO.currentDir
  let base := if path.startsWith "/" then path else cwd.toString ++ "/" ++ path
  let parts := (base.splitOn "/").filter fun part => !part.isEmpty && part != "."
  let resolved := parts.foldl (init := ([] : List String)) fun acc part =>
    if part == ".." then acc.drop 1 else part :: acc
  let lexical := "/" ++ "/".intercalate resolved.reverse
  try
    let real ← IO.FS.realPath (System.FilePath.mk lexical)
    pure real.toString
  catch _ => pure lexical

private def components (path : String) : List String := (path.splitOn "/").filter (!·.isEmpty)

private def isDirectory (path : String) : IO Bool := do
  match ← (System.FilePath.mk path).metadata.toBaseIO with
  | .ok metadata => pure (metadata.type == .dir)
  | .error _ => pure false

private def isFile (path : String) : IO Bool := do
  match ← (System.FilePath.mk path).metadata.toBaseIO with
  | .ok metadata => pure (metadata.type == .file)
  | .error _ => pure false

private partial def walkFiles (dir : String) : IO (Array String) := do
  let mut out : Array String := #[]
  for entry in ← (System.FilePath.mk dir).readDir do
    let child := (if dir == "/" then "" else dir) ++ "/" ++ entry.fileName
    if ← isDirectory child then out := out ++ (← walkFiles child)
    else if ← isFile child then out := out.push child
  return out

private def sortedStrings (items : Array String) : Array String :=
  items.qsort fun a b => compareKeys a b == .lt

/-- The host files of the roots: a file root as itself, a directory root by its supported files, sorted and distinct. -/
def hostFiles (roots : Array String) : ScanM (Array String) := do
  let mut files : Array String := #[]
  for root in roots do
    let absolute ← absolutePath root
    if ← isFile absolute then files := files.push absolute
    else if ← isDirectory absolute then
      for file in ← walkFiles absolute do
        if (extensionOf file >>= languageOfExtension).isSome then files := files.push file
    else throw { message := "Embedded source root does not exist", data := #[("root", .str absolute)] }
  pure (sortedStrings (files.foldl (fun acc file => if acc.contains file then acc else acc.push file) #[]))

/-- The runs of ASCII letters and digits in `value`. -/
private def alnumWords (value : String) : List String := Id.run do
  let mut words : List String := []
  let mut current := ""
  for c in value.toList do
    if (c.isAlpha || c.isDigit) && c.toNat < 128 then current := current.push c
    else
      unless current.isEmpty do words := current :: words
      current := ""
  unless current.isEmpty do words := current :: words
  return words.reverse

/-- A Lean identifier segment: the words of a name in capitalised form, `Generated` if none, `N` before a leading digit. -/
def namespaceSegment (value : String) : String :=
  let capitalised := String.join ((alnumWords value).map fun word =>
    match word.toLower.toList with
    | first :: rest => String.ofList (first.toUpper :: rest)
    | [] => "")
  let candidate := if capitalised.isEmpty then "Generated" else capitalised
  if candidate.toList.head?.map Char.isDigit |>.getD false then "N" ++ candidate else candidate

/-! ## Planning -/

structure Entry where
  block : Block
  ordinal : Nat
  host : String
  root : String
  relative : String
  scanPath : String
  language : String
  output : String
  leanNamespace : String
  sourceText : String
  zcSha256 : String
  zcBytes : Nat

structure Host where
  host : String
  root : String
  relative : String
  scanPath : String
  language : String
  sourceHash : String

structure Planned where
  hosts : Array Host
  scanErrors : Array J
  entries : Array Entry

/-- Each run of characters other than letters and digits becomes one underscore. -/
private def sanitizeBlockModule (blockId : String) : String := Id.run do
  let mut out := ""
  let mut inRun := false
  for c in blockId.toList do
    if (c.isAlpha || c.isDigit) && c.toNat < 128 then
      out := out.push c
      inRun := false
    else
      unless inRun do out := out.push '_'
      inRun := true
  return out

/-- The ZIL module that one block compiles from. -/
def blockSource (block : Block) : String :=
  s!"MODULE embedded.block.{sanitizeBlockModule block.blockId}.\n\n" ++ "\n".intercalate block.statements.toList ++ "\n"

private def relativeTo (root source : String) : String :=
  if root == source then fileName source
  else "/".intercalate ((components source).drop (components root).length)

private def startsWithComponents (path root : String) : Bool :=
  let p := components path
  let r := components root
  p.length ≥ r.length && (p.take r.length) == r

private def stem (relative : String) : String :=
  let name := fileName relative
  match name.splitOn "." with
  | [] | [_] => name
  | parts => if parts.getLast!.isEmpty then name else ".".intercalate parts.dropLast

private def macroTextFor (source : String) (libDir : Option String) : IO String :=
  match libDir with
  | none => pure ""
  | some dir =>
      if dir.toList.all isJavaWs then pure ""
      else do
        let files ← libraryFiles source libDir
        pure ("\n".intercalate (← files.mapM fun file => IO.FS.readFile (System.FilePath.mk file)).toList)

def scanHosts (roots : Array String) (libDir : Option String) : ScanM (Array Host × Array Entry × Array J) := do
  let mut absoluteRoots : Array String := #[]
  for root in roots do absoluteRoots := absoluteRoots.push (← absolutePath root)
  let mut hosts : Array Host := #[]
  let mut entries : Array Entry := #[]
  let mut errors : Array J := #[]
  for source in ← hostFiles roots do
    let candidates := absoluteRoots.filter (startsWithComponents source ·)
    let some root := (candidates.qsort fun a b => (components a).length > (components b).length)[0]?
      | throw { message := "Host source is outside configured roots", data := #[("source", .str source)] }
    let relative := relativeTo root source
    let rootLabel := namespaceSegment (fileName root)
    let scanPath := rootLabel ++ "/" ++ relative
    try
      let text ← IO.FS.readFile (System.FilePath.mk source)
      match scanText scanPath text (← macroTextFor source libDir) (some rootLabel) with
      | .error error =>
          errors := errors.push (.obj #[("host", .str source), ("message", .str error.message), ("data", .obj error.data)])
      | .ok report =>
          hosts := hosts.push {
            host := source
            root := root
            relative := relative
            scanPath := scanPath
            language := report.language.name
            sourceHash := report.sourceHash }
          let mut ordinal := 0
          for block in report.blocks do
            let text := blockSource block
            let segments := (components relative).dropLast.map namespaceSegment
            let fileSegment := namespaceSegment (stem relative)
            let blockSegment := s!"Block{ordinal}"
            entries := entries.push {
              block, ordinal, host := source, root, relative, scanPath, language := report.language.name,
              output := "/".intercalate (segments ++ [fileSegment, blockSegment ++ ".lean"]),
              leanNamespace := ".".intercalate (segments ++ [fileSegment, blockSegment]),
              sourceText := text, zcSha256 := Zil.Crypto.Sha256.hex text.toUTF8, zcBytes := text.toUTF8.size }
            ordinal := ordinal + 1
    catch error : IO.Error =>
      errors := errors.push (.obj #[("host", .str source), ("message", .str (toString error)), ("data", .null)])
  pure (hosts, entries, errors)

/-- Plan every block: its generated module's file and Lean namespace, with no two alike. -/
def plan (options : Options) : ScanM Planned := do
  let (hosts, scanned, scanErrors) ← scanHosts options.roots options.libDir
  let outputRoot ← absolutePath options.outputRoot
  let prefixParts := (options.namespacePrefix.splitOn ".")
  let entries := scanned.map fun entry =>
    let rootLabel := namespaceSegment (fileName entry.root)
    { entry with
      output := outputRoot ++ "/" ++ rootLabel ++ "/" ++ entry.output
      leanNamespace := ".".intercalate (prefixParts ++ [rootLabel] ++ entry.leanNamespace.splitOn ".") }
  let entries := entries.qsort fun a b =>
    match compareKeys a.host b.host with
    | .lt => true
    | .gt => false
    | .eq => a.ordinal < b.ordinal
  for (field, values) in [("output", entries.map (·.output)), ("lean-namespace", entries.map (·.leanNamespace)),
      ("block_id", entries.map (·.block.blockId))] do
    let distinct := values.foldl (fun acc value => if acc.contains value then acc else acc.push value) (#[] : Array String)
    if distinct.size != values.size then
      throw { message := "Embedded compilation plan contains collisions",
              data := #[("field", .str field), ("values", .arr (values.map .str))] }
  pure { hosts, scanErrors, entries }

/-! ## Compiling -/

/-- Compile one block's module to a Lean module, in this process. -/
def compileSource (sourceText leanNamespace : String) : Except String String := do
  let program ← (Zil.Parser.DeclarationProgram.parseText sourceText).mapError (·.render)
  let name ← Zil.Parser.nameFromToken leanNamespace
  Zil.Parser.DeclarationProgram.renderLeanModule program name

private def atomicWrite (path text : String) : IO Unit := do
  let target := System.FilePath.mk path
  if let some parent := target.parent then IO.FS.createDirAll parent
  let temporary := System.FilePath.mk (path ++ ".zil-embedded.tmp")
  IO.FS.writeFile temporary text
  IO.FS.rename temporary target

private def entryJson (entry : Entry) : Array (String × J) :=
  let block := entry.block
  let base : Array (String × J) := #[
    ("block_id", .str block.blockId), ("target", .str block.target), ("trust", .str "asserted_annotation"),
    ("start_line", .int block.startLine), ("end_line", .int block.endLine), ("source_hash", .str block.sourceHash),
    ("macro_revision", .str block.macroRevision), ("module", .str block.moduleName),
    ("namespace", .str block.nameSpace), ("project", .str block.project), ("source_span", .str block.sourceSpan),
    ("ordinal", .int entry.ordinal), ("host", .str entry.host), ("root", .str entry.root),
    ("relative", .str entry.relative), ("scan-path", .str entry.scanPath), ("language", .str entry.language),
    ("output", .str entry.output), ("lean-namespace", .str entry.leanNamespace),
    ("zc-sha256", .str entry.zcSha256), ("zc-bytes", .int entry.zcBytes)]
  match block.declarationKind with
  | some kind => base.push ("declaration_kind", .str kind)
  | none => base

private def trimmed (text : String) : String := jtrim text

private def compileEntry (options : Options) (outputRoot : String) (entry : Entry) : IO (String × J) := do
  let fields := entryJson entry
  match compileSource entry.sourceText entry.leanNamespace with
  | .error message =>
      pure ("failed", .obj (fields ++ #[("status", .str "failed"), ("phase", .str "compile"), ("exit", .int 1),
        ("error", .str (trimmed message))]))
  | .ok generated =>
      let outputSha := Zil.Crypto.Sha256.hex generated.toUTF8
      let size := generated.toUTF8.size
      let hashed : Array (String × J) := #[("output-sha256", .str outputSha), ("bytes", .int size)]
      if options.checkOnly then
        pure ("checked", .obj (fields ++ #[("status", .str "checked")] ++ hashed))
      else
        atomicWrite entry.output generated
        if !options.verifyGenerated then
          pure ("compiled", .obj (fields ++ #[("status", .str "compiled")] ++ hashed))
        else
          let existing := (← IO.getEnv "LEAN_PATH").getD ""
          let leanPath := if existing.isEmpty then outputRoot else outputRoot ++ ":" ++ existing
          let verified ← Zil.Process.run "lake" #["env", "lean", entry.output] 900000 (env := #[("LEAN_PATH", some leanPath)])
          if verified.exitCode == 0 then
            pure ("verified", .obj (fields ++ #[("status", .str "verified")] ++ hashed))
          else
            pure ("verification-failed", .obj (fields ++ #[("status", .str "verification-failed"), ("phase", .str "verify")] ++
              hashed ++ #[("exit", .int verified.exitCode), ("error", .str (trimmed verified.stderr))]))

/-- Compile every embedded block under the roots and write the manifest; the report says whether all of it passed. -/
def compileEmbedded (options : Options) : ScanM J := do
  let planned ← plan options
  let outputRoot ← absolutePath options.outputRoot
  let mut results : Array (String × J) := #[]
  for entry in planned.entries do
    results := results.push (← compileEntry options outputRoot entry)
  let accepted := if options.verifyGenerated then ["verified", "checked"] else ["compiled", "checked"]
  let count (status : String) := (results.filter (·.1 == status)).size
  let noBlockFailure := options.requireBlocks && results.isEmpty
  let failed := (results.filter fun result => !accepted.contains result.1).size
  let ok := planned.scanErrors.isEmpty && !noBlockFailure && failed == 0
  let mut rootPaths : Array String := #[]
  for root in options.roots do rootPaths := rootPaths.push (← absolutePath root)
  let hostJson (host : Host) : J := .obj #[("host", .str host.host), ("root", .str host.root),
    ("relative", .str host.relative), ("scan-path", .str host.scanPath), ("language", .str host.language),
    ("source-hash", .str host.sourceHash)]
  let report : J := .obj #[
    ("schema", .str "ZIL-EMBEDDED-MANIFEST/1"),
    ("roots", .arr (rootPaths.map .str)),
    ("output-root", .str (← absolutePath options.outputRoot)), ("namespace-prefix", .str options.namespacePrefix),
    ("check-only", .bool options.checkOnly), ("verify-generated", .bool options.verifyGenerated),
    ("require-blocks", .bool options.requireBlocks), ("ok", .bool ok),
    ("host-count", .int planned.hosts.size), ("block-count", .int results.size),
    ("verified", .int (count "verified")), ("compiled", .int (count "compiled")), ("checked", .int (count "checked")),
    ("failed", .int failed), ("hosts", .arr (planned.hosts.map hostJson)), ("scan-errors", .arr planned.scanErrors),
    ("entries", .arr (results.map (·.2))),
    ("failures", .arr (if noBlockFailure then #[.obj #[("kind", .str "no-embedded-blocks")]] else #[]))]
  let canonicalReport ← match canonical report with
    | .ok value => pure value
    | .error message => throw { message }
  atomicWrite (← absolutePath options.manifest) (write canonicalReport (escapeSlash := false) ++ "\n")
  pure report

end Zil.Embedded
