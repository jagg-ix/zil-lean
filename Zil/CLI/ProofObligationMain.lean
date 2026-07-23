import Zil.CLI.ProofObligation

private def usage : String :=
  "zilProofObligations <input.zc> [tool|-] [output|-]"

/-- Dedicated native proof-obligation governance entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [input] =>
        let ok ← Zil.CLI.proofObligationsFile input
        pure (if ok then 0 else 1)
    | [input, tool] =>
        let ok ← Zil.CLI.proofObligationsFile input tool
        pure (if ok then 0 else 1)
    | [input, tool, output] =>
        let ok ← Zil.CLI.proofObligationsFile input tool (some output)
        pure (if ok then 0 else 1)
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
