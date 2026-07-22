namespace Zil

/-- Stable external identity for a knowledge-graph node. -/
structure Node where
  id : String
  deriving Repr, BEq, Inhabited

/-- A relation endpoint is either a bound rule/query variable or a ground node. -/
inductive Term where
  | var (name : Name)
  | node (value : Node)
  deriving Repr, BEq, Inhabited

namespace Term

/-- Convert the token convention used by the standalone ZIL frontend into typed IR. -/
def ofToken (token : String) : Term :=
  if token.startsWith "?" then
    .var (Name.mkSimple (token.drop 1))
  else
    .node ⟨token⟩

#guard ofToken "?claim" == .var `claim
#guard ofToken "claim:schwarzschild" == .node ⟨"claim:schwarzschild"⟩

end Term
end Zil
