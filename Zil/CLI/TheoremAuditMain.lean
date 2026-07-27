import Zil.CLI.TheoremAudit

private def usage : String :=
  "zilTheoremAudit <input.zc> [output|-]"

/-- Dedicated native theorem-contract and external-claim audit entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [input] =>
        let ok ← Zil.CLI.theoremAuditFile input
        pure (if ok then 0 else 1)
    | [input, output] =>
        let ok ← Zil.CLI.theoremAuditFile input (some output)
        pure (if ok then 0 else 1)
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
