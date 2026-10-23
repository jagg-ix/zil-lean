import Zil.Import.Hcl
import Zil.Export.Lts

/-!
# `zilInterop`: importers and exporters between ZIL and other formats

    zilInterop import-hcl <file-or-dir> [output.zc|-] [module_name]
    zilInterop export-tla <file-or-dir> [output.tla|-] [module_name]
    zilInterop export-lean <file-or-dir> [output.lean|-] [namespace]

Exit status: 0 on success, 2 on a malformed command or an input that cannot be read.
-/

open Zil.Json

private def usage : String :=
  "zilInterop import-hcl <file-or-dir> [output.zc|-] [module_name]\n" ++
  "zilInterop export-tla <file-or-dir> [output.tla|-] [module_name]\n" ++
  "zilInterop export-lean <file-or-dir> [output.lean|-] [namespace]"

private def writeOrPrint (output : Option String) (text : String) : IO Unit :=
  match output with
  | some out => do
      if let some parent := (System.FilePath.mk out).parent then IO.FS.createDirAll parent
      IO.FS.writeFile out text
  | none => IO.print text

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  try
    match args with
    | "import-hcl" :: path :: rest =>
        let output := match rest with | out :: _ => if out == "-" then none else some out | [] => none
        let moduleName := match rest with | _ :: m :: _ => m | _ => "hcl.import"
        let report ← Zil.Import.Hcl.importPath path moduleName
        match output with
        | some out =>
            if let some parent := (System.FilePath.mk out).parent then IO.FS.createDirAll parent
            IO.FS.writeFile out report.text
            IO.println (write (.obj #[("ok", .bool true), ("path", .str path), ("files", .arr (report.files.map .str)),
              ("module", .str moduleName), ("providers", .int report.providers), ("resources", .int report.resources),
              ("data", .int report.data), ("modules", .int report.modules), ("variables", .int report.variables),
              ("outputs", .int report.outputs), ("output_path", .str out)]))
        | none => IO.print report.text
        return (0 : UInt32)
    | "export-tla" :: path :: rest =>
        let output := match rest with | out :: _ => if out == "-" then none else some out | [] => none
        let moduleName := match rest with | _ :: m :: _ => some m | _ => none
        let export_ ← Zil.Export.exportTla path moduleName
        writeOrPrint output export_.text
        if output.isSome then
          IO.println (write (.obj #[("ok", .bool true), ("path", .str path), ("files", .arr (export_.vocabulary.files.map .str)),
            ("modules", .arr (export_.vocabulary.modules.map .str)), ("module_name", .str export_.moduleName),
            ("actor_count", .int export_.vocabulary.actors.size), ("output_path", J.str output.get!)]))
        return (0 : UInt32)
    | "export-lean" :: path :: rest =>
        let output := match rest with | out :: _ => if out == "-" then none else some out | [] => none
        let namespace_ := match rest with | _ :: n :: _ => some n | _ => none
        let export_ ← Zil.Export.exportLean path namespace_
        writeOrPrint output export_.text
        if output.isSome then
          IO.println (write (.obj #[("ok", .bool true), ("path", .str path), ("files", .arr (export_.vocabulary.files.map .str)),
            ("modules", .arr (export_.vocabulary.modules.map .str)), ("namespace", .str export_.namespace_),
            ("actor_count", .int export_.vocabulary.actors.size), ("output_path", J.str output.get!)]))
        return (0 : UInt32)
    | _ =>
        IO.eprintln usage
        return (2 : UInt32)
  catch error =>
    IO.eprintln s!"{error}"
    return (2 : UInt32)
