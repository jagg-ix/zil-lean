/-!
# Running a command with a deadline

No shell: the executable and its arguments are given separately, standard output and error are collected, and a command
that runs past its deadline is killed and reported as such.
-/

namespace Zil.Process

structure Result where
  exitCode : Int
  stdout : String
  stderr : String

/-- A task that yields `value` after `ms` milliseconds, or within a slice of being cancelled. A plain long sleep would keep
the process from exiting until the deadline had passed even when it was not needed. -/
def timer {α : Type} (ms : Nat) (value : α) : IO (Task (Except IO.Error α)) :=
  IO.asTask (prio := .dedicated) do
    let mut left := ms
    while left > 0 && !(← IO.checkCanceled) do
      let slice := min left 25
      IO.sleep slice.toUInt32
      left := left - slice
    pure value

/-- Run `cmd args` and collect its output. Fails with `external-tool-timeout` after `timeoutMs`. -/
def run (cmd : String) (args : Array String) (timeoutMs : Nat) (cwd : Option System.FilePath := none)
    (env : Array (String × Option String) := #[]) (stdin : Option String := none) : IO Result := do
  let spawned ← IO.Process.spawn
    { cmd, args, cwd, env, stdin := .piped, stdout := .piped, stderr := .piped }
  let (input, child) ← spawned.takeStdin
  let out ← IO.asTask (prio := .dedicated) child.stdout.readToEnd
  let err ← IO.asTask (prio := .dedicated) child.stderr.readToEnd
  if let some text := stdin then
    try
      input.putStr text
      input.flush
    catch _ => pure ()
  -- the input handle is dropped here, closing the command's input
  let _ := input
  let waiter ← IO.asTask (prio := .dedicated) child.wait
  let deadline ← timer timeoutMs (0 : UInt32)
  let _ ← IO.waitAny [waiter, deadline]
  IO.cancel deadline
  if ← IO.hasFinished waiter then
    let code ← IO.ofExcept waiter.get
    let stdout ← IO.ofExcept out.get
    let stderr ← IO.ofExcept err.get
    return { exitCode := code.toNat, stdout, stderr }
  else
    try child.kill catch _ => pure ()
    throw (IO.userError s!"external-tool-timeout: {cmd} timed out after {timeoutMs} ms")

end Zil.Process
