import Zil.Runtime.Ingest

/-!
# Data files to and from ZIL

`importData` reads one JSON, YAML, CSV, EDN, `key=value` or text file and writes each record as ZIL facts about an
`entity:interop_record`. `convert` reads a payload in one format and writes it in another.
-/

namespace Zil.Runtime.Interop

open Zil.Json Zil.JavaText Zil.Runtime.Codec Zil.Runtime.Ingest

/-- The format a file name implies. -/
def inferFormat (path : String) : Option Format :=
  let name := (fileNameOf path).toLower
  if name.endsWith ".json" then some .json
  else if name.endsWith ".yaml" || name.endsWith ".yml" then some .yaml
  else if name.endsWith ".csv" then some .csv
  else if name.endsWith ".edn" then some .edn
  else if name.endsWith ".kv" then some .kv
  else if name.endsWith ".txt" then some .text
  else none
where
  fileNameOf (path : String) : String := (path.splitOn "/").getLast!

/-- Lower case, other characters collapsed to `_`, edge underscores dropped, `value` if nothing is left. -/
def sanitizeToken (text : String) : String := Id.run do
  let mut out := ""
  let mut inRun := false
  for c in text.toLower.toList do
    if (c.isLower || c.isDigit) && c.toNat < 128 || c == '_' || c == ':' || c == '-' || c == '.' then
      out := out.push c
      inRun := false
    else
      unless inRun do out := out.push '_'
      inRun := true
  let trimmed := String.ofList ((out.toList.dropWhile (· == '_')).reverse.dropWhile (· == '_')).reverse
  if trimmed.toList.all isJavaWs then "value" else trimmed

structure Imported where
  format : Format
  records : Nat
  facts : Nat
  text : String

/-- Records of a data file as ZIL facts. A term that is not plain is double-quoted so that the facts parse. -/
def importData (inputPath : String) (format : Option String := none) (moduleName : String := "interop.import")
    (recordPrefix : String := "interop:record") : IO Imported := do
  let fmt ← match format with
    | some name => match normalizeFormat name with
        | some f => pure f
        | none => throw (IO.userError s!"Unsupported interop format {name}")
    | none => match inferFormat inputPath with
        | some f => pure f
        | none => throw (IO.userError s!"Could not infer interop format from file extension; pass format explicitly. ({inputPath})")
  let text ← IO.FS.readFile (System.FilePath.mk inputPath)
  let payload ← match parseString fmt text #[("path", .str inputPath)] with
    | .ok value => pure value
    | .error message => throw (IO.userError message)
  let records := recordsFromDecoded payload
  let mut lines : Array String := #[]
  for (record, index) in records.zipIdx do
    let object := zcToken s!"{recordPrefix}:{index + 1}"
    lines := lines.push s!"{object}#kind@entity:interop_record."
    let fields := match record with | .obj fields => fields | other => #[("value", other)]
    for (key, value) in fields do
      lines := lines.push s!"{object}#{sanitizeToken key}@{zcToken (subjectValue value)}."
  return { format := fmt, records := records.size, facts := lines.size,
           text := s!"MODULE {moduleName}.\n\n" ++ "\n".intercalate lines.toList ++ "\n" }

/-- A payload read in one format and written in another. -/
def convert (text : String) (from_ to : Format) (opts : Opts := #[]) : Except String String := do
  let value ← parseString from_ text opts
  pure (emitString to value opts)

end Zil.Runtime.Interop
