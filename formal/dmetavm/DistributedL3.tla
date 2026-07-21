---- MODULE DistributedL3 ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

\* Distributed D-MetaVM layer:
\* - independent nodes
\* - async message channels
\* - local execution + remote request processing
\* - no blockchain semantics

CONSTANTS
  Nodes,
  Interpreters,
  Payloads,
  MaxBudget,
  MaxChannelDepth,
  MaxCompleted,
  TokenEnabled,
  LedgerEnabled,
  PoWEnabled,
  MiningEnabled

ASSUME Nodes # {}
ASSUME Interpreters # {}
ASSUME Payloads # {}
ASSUME MaxBudget \in Nat /\ MaxBudget > 0
ASSUME MaxChannelDepth \in Nat /\ MaxChannelDepth > 0
ASSUME MaxCompleted \in Nat /\ MaxCompleted > 0

VARIABLES
  nodeBudget,
  nodeMode,
  nodeRegistry,
  channels,
  completed

Vars == <<nodeBudget, nodeMode, nodeRegistry, channels, completed>>

ChannelKey == {k \in (Nodes \X Nodes) : k[1] # k[2]}

Init ==
  /\ nodeBudget = [n \in Nodes |-> MaxBudget]
  /\ nodeMode = [n \in Nodes |-> "running"]
  /\ nodeRegistry = [n \in Nodes |-> [i \in Interpreters |-> FALSE]]
  /\ channels = [k \in ChannelKey |-> <<>>]
  /\ completed = <<>>

RegisterInterpreter(n, i) ==
  /\ n \in Nodes
  /\ i \in Interpreters
  /\ nodeRegistry[n][i] = FALSE
  /\ nodeRegistry' = [nodeRegistry EXCEPT ![n][i] = TRUE]
  /\ UNCHANGED <<nodeBudget, nodeMode, channels, completed>>

LocalStep(n) ==
  /\ n \in Nodes
  /\ nodeMode[n] = "running"
  /\ nodeBudget[n] > 0
  /\ nodeBudget' = [nodeBudget EXCEPT ![n] = @ - 1]
  /\ UNCHANGED <<nodeMode, nodeRegistry, channels, completed>>

SendExec(src, dst, i, p) ==
  /\ src \in Nodes /\ dst \in Nodes /\ src # dst
  /\ i \in Interpreters /\ p \in Payloads
  /\ nodeMode[src] = "running"
  /\ nodeBudget[src] > 0
  /\ nodeRegistry[dst][i] = TRUE
  /\ LET k == <<src, dst>> IN
       /\ Len(channels[k]) < MaxChannelDepth
       /\ channels' = [channels EXCEPT ![k] = Append(@, [kind |-> "exec_remote", interpreter |-> i, payload |-> p])]
  /\ UNCHANGED <<nodeBudget, nodeMode, nodeRegistry, completed>>

ReceiveAndProcess(dst) ==
  /\ dst \in Nodes
  /\ \E src \in Nodes :
       /\ src # dst
       /\ LET k == <<src, dst>> IN
            /\ Len(channels[k]) > 0
            /\ LET msg == Head(channels[k]) IN
                 /\ channels' = [channels EXCEPT ![k] = Tail(@)]
                 /\ LET rec == [dst |-> dst, msg |-> msg] IN
                      completed' =
                        IF Len(completed) < MaxCompleted
                        THEN Append(completed, rec)
                        ELSE Append(Tail(completed), rec)
                 /\ UNCHANGED <<nodeBudget, nodeMode, nodeRegistry>>

BudgetExhausted(n) ==
  /\ n \in Nodes
  /\ nodeBudget[n] = 0
  /\ nodeMode' = [nodeMode EXCEPT ![n] = "halted"]
  /\ UNCHANGED <<nodeBudget, nodeRegistry, channels, completed>>

Stutter ==
  /\ UNCHANGED Vars

Next ==
  \/ \E n \in Nodes : LocalStep(n)
  \/ \E n \in Nodes : \E i \in Interpreters : RegisterInterpreter(n, i)
  \/ \E s \in Nodes : \E d \in Nodes : \E i \in Interpreters : \E p \in Payloads : SendExec(s, d, i, p)
  \/ \E d \in Nodes : ReceiveAndProcess(d)
  \/ \E n \in Nodes : BudgetExhausted(n)
  \/ Stutter

NoBlockchainProfile ==
  /\ TokenEnabled = FALSE
  /\ LedgerEnabled = FALSE
  /\ PoWEnabled = FALSE
  /\ MiningEnabled = FALSE

TypeOK ==
  /\ nodeBudget \in [Nodes -> Nat]
  /\ nodeMode \in [Nodes -> {"running", "halted"}]
  /\ nodeRegistry \in [Nodes -> [Interpreters -> BOOLEAN]]
  /\ channels \in [ChannelKey -> Seq( [kind : {"exec_remote"}, interpreter : Interpreters, payload : Payloads] )]
  /\ \A k \in ChannelKey : Len(channels[k]) <= MaxChannelDepth
  /\ completed \in Seq([dst : Nodes, msg : [kind : {"exec_remote"}, interpreter : Interpreters, payload : Payloads]])
  /\ Len(completed) <= MaxCompleted

BudgetNonNegative == \A n \in Nodes : nodeBudget[n] >= 0

SomeNodeIsRunning == \E n \in Nodes : nodeMode[n] = "running"

SomeNodeRunningOrAllHalted == SomeNodeIsRunning \/ (\A n \in Nodes : nodeMode[n] = "halted")

FairProgress == []SomeNodeRunningOrAllHalted

Spec == Init /\ [][Next]_Vars

THEOREM Spec => []TypeOK

=============================================================================
