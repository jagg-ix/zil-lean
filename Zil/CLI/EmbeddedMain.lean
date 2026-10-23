import Zil.Embedded.Compile

/-!
# `zilEmbedded`: ZIL blocks embedded in host-language source files

    zilEmbedded scan <file-or-dir> [output.zc|-] [module_name] [lib_dir]
    zilEmbedded snapshot <file-or-dir> <baseline.json> [lib_dir]
    zilEmbedded drift-check <file-or-dir> <baseline.json> [lib_dir]
    zilEmbedded compile [--root PATH]... [--out DIR] [--manifest FILE] [--namespace NAME] [--lib DIR]
                        [--check] [--no-verify] [--require-blocks]

`scan` prints the facts of the blocks (or writes them and prints a summary). `snapshot` records the blocks of a source
tree as a baseline. `drift-check` compares a baseline with the sources as they are now and exits 1 when they differ.
`compile` turns every block into a Lean module under `--out`, typechecks it unless `--no-verify` or `--check`, and
writes a JSON manifest; it exits 1 when any block, host file or required block fails. Exit status 2 is a malformed command or an input that cannot be read or compiled.
-/

open Zil.Json Zil.Embedded

private def usage : String :=
  "zilEmbedded scan <file-or-dir> [output.zc|-] [module_name] [lib_dir]\n" ++
  "zilEmbedded snapshot <file-or-dir> <baseline.json> [lib_dir]\n" ++
  "zilEmbedded drift-check <file-or-dir> <baseline.json> [lib_dir]\n" ++
  "zilEmbedded compile [--root PATH]... [--out DIR] [--manifest FILE] [--namespace NAME] [--lib DIR]\n" ++
  "                    [--check] [--no-verify] [--require-blocks]"

private def report (error : ScanError) : IO UInt32 := do
  IO.eprintln error.message
  unless error.data.isEmpty do IO.eprintln (write (.obj error.data) (escapeSlash := false))
  return 2

private def parseCompile : List String → Options → Except String (Option Options)
  | [], options => .ok (some options)
  | "--help" :: _, _ => .ok none
  | "--root" :: value :: rest, options => parseCompile rest { options with roots := options.roots.push value }
  | "--out" :: value :: rest, options => parseCompile rest { options with outputRoot := value }
  | "--manifest" :: value :: rest, options => parseCompile rest { options with manifest := value }
  | "--namespace" :: value :: rest, options => parseCompile rest { options with namespacePrefix := value }
  | "--lib" :: value :: rest, options => parseCompile rest { options with libDir := some value }
  | "--check" :: rest, options => parseCompile rest { options with checkOnly := true }
  | "--no-verify" :: rest, options => parseCompile rest { options with verifyGenerated := false }
  | "--require-blocks" :: rest, options => parseCompile rest { options with requireBlocks := true }
  | [flag], _ => .error s!"Missing embedded compiler option value or unknown argument: {flag}"
  | flag :: _, _ => .error s!"Unknown embedded compiler argument: {flag}"

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  let run (action : ScanM UInt32) : IO UInt32 := do
    try
      match ← action.run with
      | .ok code => pure code
      | .error error => report error
    catch error : IO.Error =>
      IO.eprintln (toString error)
      pure 2
  match args with
  | "scan" :: path :: rest =>
      let output := match rest with | out :: _ => if out == "-" then none else some out | [] => none
      let moduleName := match rest with | _ :: m :: _ => m | _ => "embedded.annotations"
      let libDir := match rest with | _ :: _ :: l :: _ => some l | _ => none
      run do
        let scan ← scanPath path moduleName output libDir
        if output.isSome then
          IO.println (write (.obj #[("ok", .bool true), ("path", .str path), ("module", .str moduleName),
            ("file_count", .int scan.reports.size), ("block_count", .int scan.blockCount)]) (escapeSlash := false))
        else IO.print scan.text
        pure 0
  | "snapshot" :: path :: baseline :: rest =>
      run do
        let scan ← scanPath path (libDir := rest.head?)
        let snapshot ← writeSnapshot scan baseline
        IO.println (write (.obj #[("ok", .bool true), ("output", .str baseline), ("format", .str snapshotFormat),
          ("block_count", .int ((snapshot.get? "blocks" >>= J.asArr?).getD #[]).size)]) (escapeSlash := false))
        pure 0
  | "drift-check" :: path :: baseline :: rest =>
      run do
        let drift ← driftCheck path baseline rest.head?
        IO.println (write drift (escapeSlash := false))
        pure (if drift.get? "drift" == some (.bool true) then 1 else 0)
  | "compile" :: rest =>
      match parseCompile rest { roots := #[] } with
      | .error message => IO.eprintln message; IO.eprintln usage; pure 2
      | .ok none => IO.println usage; pure 0
      | .ok (some options) =>
          let options := if options.roots.isEmpty then { options with roots := #["."] } else options
          run do
            let manifest ← compileEmbedded options
            let ok := manifest.get? "ok" == some (.bool true)
            IO.println (if ok then "embedded ZIL compilation passed" else "embedded ZIL compilation failed")
            pure (if ok then 0 else 1)
  | _ =>
      IO.eprintln usage
      pure 2
