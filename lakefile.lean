import Lake
open Lake DSL

package «zil-lean» where
  version := v!"0.1.0"

lean_lib Zil where
  roots := #[`Zil]

lean_exe zilLeanTests where
  root := `Zil.Test.Main

lean_exe zil where
  root := `Zil.CLI.Main

lean_exe zilActionToken where
  root := `Zil.CLI.ActionTokenMain

lean_exe zilTokenLifecycle where
  root := `Zil.CLI.TokenLifecycleMain

lean_exe zilRecoveryAudit where
  root := `Zil.CLI.RecoveryAuditMain

lean_exe zilAgentContext where
  root := `Zil.CLI.AgentContextMain

lean_exe zilProofObligations where
  root := `Zil.CLI.ProofObligationMain

lean_exe zilTheoremAudit where
  root := `Zil.CLI.TheoremAuditMain
