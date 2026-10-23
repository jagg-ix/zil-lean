import Zil.Release.Attestation

/-! # `zilRelease attest <release-request.json> <attestation.json>` -/

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  match args with
  | ["attest", request, output] =>
      try
        let attestation ← Zil.Release.attestFile request output
        IO.println (← Zil.Release.render attestation)
        return if attestation.get? "ok" == some (.bool true) then (0 : UInt32) else 1
      catch error =>
        IO.eprintln s!"{error}"
        return (2 : UInt32)
  | _ =>
      IO.eprintln "zilRelease attest <release-request.json> <attestation.json>"
      return (2 : UInt32)
