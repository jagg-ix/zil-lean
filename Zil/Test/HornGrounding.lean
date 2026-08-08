import Zil.Datalog.HornGrounding

namespace Zil.Test.HornGrounding

/-- A real declaration that both grounds the contract's `lean:` requirement and
serves as its witness. -/
theorem groundingWitness : True := trivial

-- A grounded contract: its one `lean:` requirement resolves and its witness
-- exists, so `#zil_horn_grounding` must certify it.
zil_file_contract zil.test.hornGrounding where
  promises "A grounded test contract exercising the Horn grounding command."
  at_level bridge_theorem
  contract_status scaffold
  requires_objects ["lean:Zil.Test.HornGrounding.groundingWitness"]
  forbids_substitutes ["none"]
  witnessed_by [groundingWitness]

-- Both commands must succeed (elaboration would error otherwise, failing the build).
#zil_horn_grounding zil.test.hornGrounding
#zil_horn_grounding_all

end Zil.Test.HornGrounding
