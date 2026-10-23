import Zil.Plugin.Evidence
import Zil.Control.Capability

/-!
# Extension registry

Registers extensions from validated manifests with collision prevention and failure isolation. An extension can neither
shadow a built-in command or capability, nor claim authority its manifest does not declare, nor raise its evidence above
its manifest's ceiling. One that fails to start, or fails while running, is quarantined: its commands stop being
available and nothing it produced is published.
-/

namespace Zil.Plugin

open Zil.Json Zil.Control

structure CommandDescriptor where
  summary : String := ""
  arguments : Array String := #[]
  authority : String

/-- A live extension: what it provides and how to call it. -/
structure Extension where
  manifest : Manifest
  capabilities : Array String := #[]
  commands : Array (String × CommandDescriptor) := #[]
  start : IO Unit := pure ()
  stop : IO Unit := pure ()
  invoke : String → Array String → IO J := fun command _ => throw (IO.userError s!"unknown-extension-command: {command}")
  /-- Produce evidence parts for a request: each part is turned into an envelope by the registry. -/
  evidence : Option (J → IO (Array Evidence.Request)) := none

structure Entry where
  manifest : Manifest
  fingerprint : String
  extension : Extension
  status : String
  error : Option String := none

structure Registry where
  workerAvailable : Bool
  extensions : IO.Ref (Array (String × Entry))
  commands : IO.Ref (Array (String × (String × CommandDescriptor)))
  capabilities : IO.Ref (Array (String × Array String))
  closed : IO.Ref Bool

def Registry.create (workerAvailable : Bool := false) : IO Registry := do
  return { workerAvailable, extensions := ← IO.mkRef #[], commands := ← IO.mkRef #[],
           capabilities := ← IO.mkRef #[], closed := ← IO.mkRef false }

private def fail (kind message : String) : IO α := throw (IO.userError s!"{kind}: {message}")

private def ensureOpen (registry : Registry) : IO Unit := do
  if ← registry.closed.get then fail "registry-closed" "extension registry is closed"

/-- Commands the program already owns: every exchange operation and every command an inventory capability names. -/
def builtInCommands : List String :=
  (["parse", "compile", "expand", "conformance", "query", "authorize", "impact", "recovery-audit"] ++
    Capability.inventory.flatMap (·.commands)).eraseDups

def builtInCapabilities : List String := Capability.inventory.map (·.id)

private def runtimeCapabilityIds (registry : Registry) : List String :=
  Capability.inventory.filterMap fun c => if c.operation.isNone || registry.workerAvailable then some c.id else none

private def availableRequirements (registry : Registry) : IO (List String) := do
  let extensions ← registry.extensions.get
  let provided ← registry.capabilities.get
  let outputs := extensions.toList.flatMap fun (_, e) => if e.status == "active" then e.manifest.outputs.toList else []
  return [manifestSchema, Evidence.schema, Capability.schema] ++
    (if registry.workerAvailable then [Zil.Exchange.schema] else []) ++ runtimeCapabilityIds registry ++
    provided.toList.map (·.1) ++ outputs

private def quarantine (registry : Registry) (id message : String) : IO Unit :=
  registry.extensions.modify fun entries =>
    entries.map fun (key, entry) => if key == id then (key, { entry with status := "quarantined", error := some message }) else (key, entry)

private def messageOf (error : IO.Error) : String := toString error

/-- Validate, start and register one extension. Returns the registered manifest with its fingerprint. -/
def Registry.register (registry : Registry) (extension : Extension) : IO J := do
  ensureOpen registry
  let manifest ← match validate extension.manifest with
    | .ok m => pure m
    | .error message => fail "extension-manifest-error" message
  let fingerprint ← match fingerprint manifest with | .ok f => pure f | .error m => fail "extension-manifest-error" m
  -- requirements
  let available ← availableRequirements registry
  let missing := manifest.requires.toList.filter (!available.contains ·)
  unless missing.isEmpty do
    fail "extension-requirement-error" s!"extension requirements are unavailable: {missing}"
  let id := manifest.id
  let capabilities := (extension.capabilities.qsort (· < ·)).foldl
    (fun out v => if out.back? == some v then out else out.push v) #[]
  -- the commands may not claim an authority the manifest does not
  for (command, descriptor) in extension.commands do
    unless descriptor.authority == manifest.authority do
      fail "extension-contract-error" s!"extension command authority disagrees with manifest ({command})"
    if descriptor.authority == "lean" || descriptor.authority == "shared" then
      unless manifest.trusted do
        fail "extension-contract-error" s!"an extension that is not trusted cannot claim Lean or shared authority ({command})"
  if (← registry.extensions.get).any (·.1 == id) then fail "extension-collision" s!"extension is already registered ({id})"
  unless manifest.capabilities == capabilities do
    fail "extension-contract-error" s!"extension capabilities disagree with its manifest ({id})"
  let commandIds := extension.commands.map (·.1)
  if let some clash := commandIds.find? builtInCommands.contains then
    fail "command-shadowing" s!"extension command shadows a built-in command ({clash})"
  let registeredCommands ← registry.commands.get
  if let some clash := commandIds.find? fun c => registeredCommands.any (·.1 == c) then
    fail "command-shadowing" s!"extension command is already registered ({clash})"
  if let some clash := capabilities.find? builtInCapabilities.contains then
    fail "capability-shadowing" s!"extension capability shadows an authoritative capability ({clash})"
  registry.extensions.modify (·.push (id, { manifest, fingerprint, extension, status := "starting" }))
  try
    extension.start
    registry.extensions.modify fun entries =>
      entries.map fun (key, entry) => if key == id then (key, { entry with status := "active" }) else (key, entry)
    registry.commands.modify (· ++ extension.commands.map fun (c, d) => (c, (id, d)))
    registry.capabilities.modify fun current =>
      capabilities.foldl (fun out capability =>
        match out.findIdx? (·.1 == capability) with
        | some i => out.set! i (capability, (out[i]!.2.push id))
        | none => out.push (capability, #[id])) current
    match withFingerprint manifest with
    | .ok json => return json
    | .error message => fail "extension-manifest-error" message
  catch error =>
    quarantine registry id (messageOf error)
    fail "extension-startup-failure" s!"extension startup failed ({id}): {messageOf error}"

def Registry.entry? (registry : Registry) (id : String) : IO (Option Entry) := do
  return ((← registry.extensions.get).find? (·.1 == id)).map (·.2)

def Registry.registered (registry : Registry) : IO J := do
  return .arr <| (← registry.extensions.get).map fun (id, entry) =>
    .obj #[("id", .str id), ("version", .str entry.manifest.version), ("status", .str entry.status),
           ("fingerprint", .str entry.fingerprint)]

/-- Run `action` for an extension; a failure quarantines it. -/
private def guarded (registry : Registry) (id : String) (action : IO α) : IO α := do
  try action
  catch error =>
    quarantine registry id (messageOf error)
    fail "extension-failure" s!"extension invocation failed ({id}): {messageOf error}"

/-- Invoke one registered command. -/
def Registry.invokeCommand (registry : Registry) (command : String) (arguments : Array String) : IO J := do
  ensureOpen registry
  let some (id, _) := (← registry.commands.get).find? (·.1 == command) |>.map (·.2)
    | fail "unknown-extension-command" s!"extension command was not found ({command})"
  let some entry ← registry.entry? id | fail "unknown-extension-command" s!"extension command was not found ({command})"
  unless entry.status == "active" do fail "extension-unavailable" s!"extension command is unavailable ({command}, {entry.status})"
  let result ← guarded registry id (entry.extension.invoke command arguments)
  return .obj #[("extension_id", .str id), ("extension_version", .str entry.manifest.version),
                ("command", .str command), ("result", result)]

/-- Produce evidence envelopes through a registered extension, checking each against the manifest. -/
def Registry.produceEvidence (registry : Registry) (id : String) (request : J) : IO (Array J) := do
  ensureOpen registry
  let some entry ← registry.entry? id | fail "extension-unavailable" s!"extension evidence producer is unavailable ({id})"
  unless entry.status == "active" do fail "extension-unavailable" s!"extension evidence producer is unavailable ({id}, {entry.status})"
  let some produce := entry.extension.evidence | fail "extension-contract-error" s!"extension does not provide evidence ({id})"
  guarded registry id do
    let parts ← produce request
    let mut out := #[]
    for part in parts do
      let envelope ← match Evidence.make { part with manifest := entry.manifest } with
        | .ok e => pure e
        | .error message => fail "evidence-error" message
      let _ ← match Evidence.validate envelope with | .ok e => pure e | .error m => fail "evidence-error" m
      unless envelope.getStr? "authority" == some entry.manifest.authority || part.authority.isSome do
        fail "evidence-error" s!"extension evidence authority disagrees with manifest ({id})"
      out := out.push envelope
    return out

/-- Stop and remove one extension, its commands and its capabilities. -/
def Registry.unregister (registry : Registry) (id : String) : IO Bool := do
  let some entry ← registry.entry? id | return false
  try entry.extension.stop catch error => quarantine registry id (messageOf error)
  registry.commands.modify fun commands => commands.filter fun (_, (owner, _)) => owner != id
  registry.capabilities.modify fun capabilities =>
    capabilities.filterMap fun (c, providers) =>
      let remaining := providers.filter (· != id)
      if remaining.isEmpty then none else some (c, remaining)
  registry.extensions.modify (·.filter (·.1 != id))
  return true

def Registry.close (registry : Registry) : IO Unit := do
  unless ← registry.closed.get do
    registry.closed.set true
    for (id, _) in (← registry.extensions.get).reverse do
      try let _ ← registry.unregister id catch _ => pure ()

/-- Every `extension.json` under the given roots, in path order. -/
partial def discoverManifests (roots : Array System.FilePath) : IO (Array System.FilePath) := do
  let rec walk (dir : System.FilePath) : IO (Array System.FilePath) := do
    let mut out := #[]
    for entry in ← dir.readDir do
      let path := entry.path
      if ← path.isDir then out := out ++ (← walk path)
      else if entry.fileName == "extension.json" then out := out.push path
    return out
  let mut found := #[]
  for root in roots do
    if ← root.isDir then found := found ++ (← walk root)
    else if ← root.pathExists then
      if root.fileName == some "extension.json" then found := found.push root
  return found.qsort fun a b => compareKeys a.toString b.toString == .lt

end Zil.Plugin
