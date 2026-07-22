import Lake
open Lake DSL

package «zil-lean» where
  version := v!"0.1.0"

lean_lib Zil where
  roots := #[`Zil]

lean_exe zilLeanTests where
  root := `Zil.Test.Main
