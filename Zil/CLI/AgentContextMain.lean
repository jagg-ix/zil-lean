import Zil.CLI.AgentContext

private def usage : String :=
  "zilAgentContext <input.zc> <task-id> <agent-id> <scope> <changed-nodes> " ++
  "[queries|-] [formalization-targets|-] [output|-]"

/-- Dedicated native entry point for deterministic agent context bundles. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [input, task, agent, scope, changed] =>
        let complete ← Zil.CLI.agentContextFile input task agent scope changed
        pure (if complete then 0 else 1)
    | [input, task, agent, scope, changed, queries] =>
        let complete ← Zil.CLI.agentContextFile input task agent scope changed queries
        pure (if complete then 0 else 1)
    | [input, task, agent, scope, changed, queries, targets] =>
        let complete ← Zil.CLI.agentContextFile input task agent scope changed queries targets
        pure (if complete then 0 else 1)
    | [input, task, agent, scope, changed, queries, targets, output] =>
        let complete ← Zil.CLI.agentContextFile input task agent scope changed queries targets (some output)
        pure (if complete then 0 else 1)
    | _ => IO.eprintln usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
