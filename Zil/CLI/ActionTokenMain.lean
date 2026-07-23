import Zil.CLI.ActionToken

private def usage : String :=
  "zilActionToken <input.zc> <request-node> [output|-]"

/-- Dedicated native action-token issuance entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [input, request] =>
        let ok ← Zil.CLI.actionTokenFile input request
        pure (if ok then 0 else 1)
    | [input, request, output] =>
        let ok ← Zil.CLI.actionTokenFile input request (some output)
        pure (if ok then 0 else 1)
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
