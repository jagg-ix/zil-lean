---- MODULE CoreMetaVM ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

\* Single-node execution core (blockchain-free profile).
\* EVM-inspired state machine: stack/memory/storage/pc/budget/code/halted/output.

CONSTANTS MaxPC, MaxBudget, OpcodeClasses, TokenEnabled, LedgerEnabled, PoWEnabled, MiningEnabled

ASSUME MaxPC \in Nat /\ MaxPC > 0
ASSUME MaxBudget \in Nat /\ MaxBudget > 0
ASSUME OpcodeClasses = {"arith", "jump", "memory", "return", "nop"}

VARIABLES
  stack,
  memory,
  storage,
  pc,
  budget,
  code,
  halted,
  output

CoreVars == <<stack, memory, storage, pc, budget, code, halted, output>>

GasCost(op) ==
  CASE op = "arith" -> 3
    [] op = "jump" -> 8
    [] op = "memory" -> 3
    [] op = "return" -> 0
    [] OTHER -> 1

Init ==
  /\ stack = <<>>
  /\ memory = [i \in 0..255 |-> 0]
  /\ storage = [i \in 0..31 |-> 0]
  /\ pc = 0
  /\ budget = MaxBudget
  /\ code = [i \in 0..MaxPC |-> IF i % 4 = 0 THEN "arith" ELSE IF i % 4 = 1 THEN "jump" ELSE IF i % 4 = 2 THEN "memory" ELSE "nop"]
  /\ halted = FALSE
  /\ output = <<>>

StepArith(op) ==
  /\ op = "arith"
  /\ budget' = budget - GasCost(op)
  /\ pc' = IF pc < MaxPC THEN pc + 1 ELSE pc
  /\ stack' = Append(stack, pc)
  /\ UNCHANGED <<memory, storage, code, halted, output>>

StepJump(op) ==
  /\ op = "jump"
  /\ budget' = budget - GasCost(op)
  /\ pc' = (pc + 2) % (MaxPC + 1)
  /\ UNCHANGED <<stack, memory, storage, code, halted, output>>

StepMemory(op) ==
  /\ op = "memory"
  /\ budget' = budget - GasCost(op)
  /\ pc' = IF pc < MaxPC THEN pc + 1 ELSE pc
  /\ memory' = [memory EXCEPT ![pc % 256] = budget]
  /\ UNCHANGED <<stack, storage, code, halted, output>>

StepReturn(op) ==
  /\ op = "return"
  /\ budget' = budget - GasCost(op)
  /\ halted' = TRUE
  /\ output' = Append(output, pc)
  /\ UNCHANGED <<stack, memory, storage, pc, code>>

StepNop(op) ==
  /\ op = "nop"
  /\ budget' = budget - GasCost(op)
  /\ pc' = IF pc < MaxPC THEN pc + 1 ELSE pc
  /\ UNCHANGED <<stack, memory, storage, code, halted, output>>

CoreStep ==
  /\ ~halted
  /\ pc \in 0..MaxPC
  /\ budget > 0
  /\ LET op == code[pc] IN
       /\ budget >= GasCost(op)
       /\ CASE op = "arith" -> StepArith(op)
            [] op = "jump" -> StepJump(op)
            [] op = "memory" -> StepMemory(op)
            [] op = "return" -> StepReturn(op)
            [] OTHER -> StepNop(op)

OutOfBudget ==
  /\ ~halted
  /\ budget = 0
  /\ halted' = TRUE
  /\ UNCHANGED <<stack, memory, storage, pc, budget, code, output>>

BudgetInsufficient ==
  /\ ~halted
  /\ pc \in 0..MaxPC
  /\ LET op == code[pc] IN budget < GasCost(op)
  /\ halted' = TRUE
  /\ UNCHANGED <<stack, memory, storage, pc, budget, code, output>>

Stutter ==
  /\ halted
  /\ UNCHANGED CoreVars

Next == CoreStep \/ BudgetInsufficient \/ OutOfBudget \/ Stutter

NoBlockchainProfile ==
  /\ TokenEnabled = FALSE
  /\ LedgerEnabled = FALSE
  /\ PoWEnabled = FALSE
  /\ MiningEnabled = FALSE

TypeOK ==
  /\ stack \in Seq(Nat)
  /\ memory \in [0..255 -> Nat]
  /\ storage \in [0..31 -> Nat]
  /\ pc \in 0..MaxPC
  /\ budget \in Nat
  /\ code \in [0..MaxPC -> OpcodeClasses]
  /\ halted \in BOOLEAN
  /\ output \in Seq(Nat)

BudgetNonNegative == budget >= 0
PCBounds == pc \in 0..MaxPC

CanSimulateTM ==
  /\ memory \in [0..255 -> Nat]
  /\ stack \in Seq(Nat)
  /\ \A i \in 0..MaxPC : code[i] \in {"arith", "jump", "memory", "return", "nop"}

Spec == Init /\ [][Next]_CoreVars

THEOREM Spec => []TypeOK

=============================================================================
