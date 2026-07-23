import Zil.CLI.RecoveryAudit

private def usage : String :=
  "zilRecoveryAudit <input.zc> <request-node> [output|-]"

/-- Dedicated native postcondition verification and recovery-audit entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [input, request] =>
        let safe ← Zil.CLI.recoveryAuditFile input request
        pure (if safe then 0 else 1)
    | [input, request, output] =>
        let safe ← Zil.CLI.recoveryAuditFile input request (some output)
        pure (if safe then 0 else 1)
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
