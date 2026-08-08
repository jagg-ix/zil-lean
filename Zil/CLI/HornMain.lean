import Zil.Horn

namespace Zil.CLI.Horn

def usage : String :=
  "zilHorc <program.hn> <query> [depth]\n" ++
  "\n" ++
  "Examples:\n" ++
  "  zilHorc list.hn 'member(X, cons(nil,1))' 16\n" ++
  "  zilHorc map.hn 'maps_to(cons(cons(nil,a,0),b,1), K, V)' 32\n"

def loadProgram (path : String) : IO Zil.Horn.Program := do
  match ← Zil.Horn.Parser.parseFile path with
  | .ok program => pure program
  | .error error => throw <| IO.userError s!"{path}:{error.render}"

def loadGoals (text : String) : IO (List Zil.Horn.Atom) :=
  match Zil.Horn.Parser.parseGoalsText text with
  | .ok goals => pure goals
  | .error error => throw <| IO.userError s!"query:{error.render}"

def renderSolution (index : Nat) (solution : Zil.Horn.Solution) : String :=
  s!"solution {index + 1} (depth {solution.depth}): " ++
    Zil.Horn.renderSubstitution solution.substitution

def run (path query : String) (depth : Nat) : IO Bool := do
  let program ← loadProgram path
  let goals ← loadGoals query
  let rawResult := Zil.Horn.solveDepth program goals depth
  let result := rawResult.onlyCertified program goals
  if result.solutions.length != rawResult.solutions.length then
    throw <| IO.userError "internal error: one or more solutions failed certificate replay"
  for entry in result.solutions.zipIdx do
    IO.println (renderSolution entry.2 entry.1 ++ " [certified]")
  if result.solutions.isEmpty then IO.println "no solution within depth bound"
  if result.cutoff then IO.println s!"cutoff: search may continue below depth {depth}"
  else IO.println "complete within depth bound: no branch was cut off"
  pure !result.solutions.isEmpty

end Zil.CLI.Horn

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | [path, query] =>
        let found ← Zil.CLI.Horn.run path query 32
        pure (if found then 0 else 1)
    | [path, query, depthText] =>
        let depth ← match depthText.toNat? with
          | some value => pure value
          | none => throw <| IO.userError "depth must be a natural number"
        let found ← Zil.CLI.Horn.run path query depth
        pure (if found then 0 else 1)
    | _ => IO.eprintln Zil.CLI.Horn.usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
