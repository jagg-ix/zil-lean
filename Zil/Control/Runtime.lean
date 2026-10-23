import Zil.Control.Capability
import Zil.Worker.Pool

/-!
# Control plane

Dispatches the Lean-authoritative exchange operations through supervised workers: the operation must be owned by a Lean
capability, the request is bound to the input's bytes, and the response comes back verified and byte-attested.
-/

namespace Zil.Control.Runtime

open Zil.Worker Zil.Json

def defaultPoolSize : Nat := 2

structure ControlPlane where
  pool : Pool
  closed : IO.Ref Bool

def start (poolSize : Nat := defaultPoolSize) (options : Options := {}) : IO ControlPlane := do
  match Capability.validate with
  | .ok () => pure ()
  | .error message => throw (IO.userError s!"configuration-error: {message}")
  return { pool := ← startPool poolSize options, closed := ← IO.mkRef false }

def stop (plane : ControlPlane) : IO Unit := do
  unless ← plane.closed.get do
    plane.closed.set true
    plane.pool.stop

structure CommandOptions where
  baseRevision : String := "-"
  requestId : Option String := none
  timeoutMs : Option Nat := none

/-- A fresh request identifier. -/
private def freshRequestId : IO String := do
  let bytes ← IO.getRandomBytes 16
  return "request:" ++ (Zil.Crypto.Sha256.toHex bytes).take 32

/-- Invoke one Lean-authoritative operation and return the verified exchange response. -/
def execute (plane : ControlPlane) (operation inputPath : String) (arguments : Array String := #[])
    (options : CommandOptions := {}) : IO Response := do
  if ← plane.closed.get then throw (IO.userError "control-plane-closed: control plane is closed")
  if inputPath.all Char.isWhitespace then throw (IO.userError "invalid-request: control-plane operation requires an input path")
  match Capability.requireLeanOperation operation with
  | .error message => throw (IO.userError s!"unknown-command: {message}")
  | .ok capability =>
      let requestId ← match options.requestId with | some id => pure id | none => freshRequestId
      let request ← buildRequest requestId operation inputPath options.baseRevision arguments
        (some (capability.operation.bind Zil.Exchange.requiredCapability? |>.toArray))
      plane.pool.invoke request (← match options.timeoutMs with | some ms => pure ms | none => configuredTimeoutMs)

/-- The authoritative payload, or a semantic-operation error. Transport failures stay transport failures. -/
def payload (response : Response) : IO String := do
  if response.status == "ok" then return response.payload
  throw (IO.userError s!"semantic-operation-error: Lean-authoritative operation failed ({response.status}): {response.errors}")

def withControlPlane (poolSize : Nat) (options : Options) (action : ControlPlane → IO α) : IO α := do
  let plane ← start poolSize options
  try
    let result ← action plane
    stop plane
    return result
  catch error =>
    try stop plane catch _ => pure ()
    throw error

end Zil.Control.Runtime
