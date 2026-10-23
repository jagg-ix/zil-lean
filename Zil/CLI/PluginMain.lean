import Zil.Plugin.Extensions
import Zil.Control.Runtime

/-!
# `zilPlugin`

    zilPlugin list [ROOT...]
    zilPlugin inspect <extension.json>
    zilPlugin run <extension.json> <command> [arguments...] [--config FILE]
    zilPlugin evidence <extension.json> <request.json|edn> [--config FILE]

Exit status: 0 on success, 2 on a malformed command or a failing extension.
-/

open Zil.Json Zil.Plugin

private def usage : String :=
  "zilPlugin list [ROOT...]\n" ++
  "zilPlugin inspect <extension.json>\n" ++
  "zilPlugin run <extension.json> <command> [arguments...] [--config FILE]\n" ++
  "zilPlugin evidence <extension.json> <request.json|edn> [--config FILE]"

private def usageError : IO α := throw (IO.userError s!"invalid-command: {usage}")

private def loadData (path : String) : IO J := do
  let text ← IO.FS.readFile path
  let parsed := if path.endsWith ".edn" then Zil.Edn.readCanonical text else Zil.Json.parse text
  match parsed with
  | .ok value => pure value
  | .error message => throw (IO.userError s!"invalid-command: cannot read {path}: {message}")

/-- Split `--config FILE` from the positional arguments. -/
private def extractConfig : List String → IO (List String × J)
  | [] => pure ([], .obj #[])
  | "--config" :: path :: rest => do
      let (positional, _) ← extractConfig rest
      pure (positional, ← loadData path)
  | ["--config"] => throw (IO.userError "invalid-command: --config requires a file")
  | arg :: rest => do
      let (positional, config) ← extractConfig rest
      pure (arg :: positional, config)

/-- The worker is needed only when a manifest requires an exchange capability. -/
private def needsWorker (manifest : Manifest) : Bool :=
  manifest.requires.any fun r =>
    r == Zil.Exchange.schema || (Zil.Control.Capability.inventory.any fun c => c.operation.isSome && c.id == r)

private def printJson (value : J) : IO Unit := IO.println (write value)

private def withRegistry (manifestPath : String) (action : Registry → IO α) : IO α := do
  let manifest ← Zil.Plugin.read manifestPath
  let registry ← Registry.create (needsWorker manifest)
  try
    let result ← action registry
    registry.close
    return result
  catch error =>
    try registry.close catch _ => pure ()
    throw error

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  try
    match args with
    | "list" :: roots =>
        let roots : Array System.FilePath := (if roots.isEmpty then ["extensions"] else roots).toArray.map System.FilePath.mk
        let mut rows := #[]
        for path in ← discoverManifests roots do
          let manifest ← Zil.Plugin.read path
          match withFingerprint manifest with
          | .ok json => rows := rows.push (.obj #[("path", .str (← absolutePath path).toString), ("id", .str manifest.id),
              ("version", .str manifest.version), ("runtime", .str manifest.runtime), ("authority", .str manifest.authority),
              ("capabilities", .arr (manifest.capabilities.map .str)),
              ("fingerprint", json.get? "fingerprint" |>.getD .null)])
          | .error message => throw (IO.userError s!"extension-manifest-error: {message}")
        printJson (.arr rows)
        return (0 : UInt32)
    | ["inspect", path] =>
        match withFingerprint (← Zil.Plugin.read path) with
        | .ok json => printJson json; return (0 : UInt32)
        | .error message => throw (IO.userError s!"extension-manifest-error: {message}")
    | "run" :: path :: command :: rest =>
        let (arguments, config) ← extractConfig rest
        let result ← withRegistry path fun registry => do
          let extension ← loadExtension path config
          let _ ← registry.register extension
          registry.invokeCommand command arguments.toArray
        printJson result
        return (0 : UInt32)
    | "evidence" :: path :: requestPath :: rest =>
        let (extra, config) ← extractConfig rest
        unless extra.isEmpty do usageError
        let request ← loadData requestPath
        let result ← withRegistry path fun registry => do
          let extension ← loadExtension path config
          let _ ← registry.register extension
          registry.produceEvidence extension.manifest.id request
        printJson (.arr result)
        return (0 : UInt32)
    | _ => usageError
  catch error =>
    IO.eprintln s!"{error}"
    return (2 : UInt32)
