import Zil.Worker.Client

/-!
# Bounded worker pool

A fixed number of supervised workers. A worker is reused while it stays healthy and is replaced after a transport
failure; asking for one when all are busy waits up to the deadline.
-/

namespace Zil.Worker

structure Pool where
  options : Options
  available : IO.Ref (List Worker)
  all : IO.Ref (List Worker)
  closed : IO.Ref Bool

def startPool (size : Nat := 1) (options : Options := {}) : IO Pool := do
  if size == 0 then throw (IO.userError "worker pool size must be positive")
  let mut started : List Worker := []
  try
    for _ in [0:size] do
      started := (← startWorker options) :: started
  catch error =>
    for worker in started do
      try worker.child.kill catch _ => pure ()
    throw error
  return { options, available := ← IO.mkRef started, all := ← IO.mkRef started, closed := ← IO.mkRef false }

private def acquire (pool : Pool) (timeoutMs : Nat) : IO Worker := do
  if ← pool.closed.get then transportError "worker pool is closed"
  let deadline := (← IO.monoMsNow) + timeoutMs
  repeat
    let taken ← pool.available.modifyGet fun workers =>
      match workers with
      | [] => (none, [])
      | worker :: rest => (some worker, rest)
    if let some worker := taken then return worker
    if (← IO.monoMsNow) ≥ deadline then
      transportError s!"timed out waiting for a Lean worker ({timeoutMs} ms)"
    IO.sleep 5
  transportError "unreachable"

private def discard (pool : Pool) (worker : Worker) : IO Unit := do
  try worker.child.kill catch _ => pure ()
  try let _ ← stopWorker worker catch _ => pure ()
  pool.all.modify fun workers => workers.filter fun w => w.child.pid != worker.child.pid
  unless ← pool.closed.get do
    try
      let replacement ← startWorker pool.options
      pool.all.modify (replacement :: ·)
      pool.available.modify (replacement :: ·)
    catch _ => pure ()

private def release (pool : Pool) (worker : Worker) : IO Unit := do
  if ← pool.closed.get then
    try let _ ← stopWorker worker catch _ => pure ()
  else if ← alive worker then
    pool.available.modify (worker :: ·)
  else
    discard pool worker

/-- Send a request through a pooled worker. A transport failure discards the worker and replaces it. -/
def Pool.invoke (pool : Pool) (request : Zil.Exchange.Request) (timeoutMs : Nat := defaultTimeoutMs) : IO Response := do
  let worker ← acquire pool timeoutMs
  try
    let response ← Worker.invoke worker request timeoutMs
    release pool worker
    return response
  catch error =>
    let transport := match error with | .userError text => text.startsWith "transport-error" | _ => true
    if transport then discard pool worker else release pool worker
    throw error

def Pool.stop (pool : Pool) : IO Unit := do
  pool.closed.set true
  for worker in ← pool.all.get do
    try worker.child.kill catch _ => pure ()
    try let _ ← stopWorker worker catch _ => pure ()
  pool.available.set []
  pool.all.set []

end Zil.Worker
