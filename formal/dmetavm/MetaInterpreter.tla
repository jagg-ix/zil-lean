---- MODULE MetaInterpreter ----
EXTENDS CoreMetaVM, Naturals, Sequences, FiniteSets, TLC

\* Meta layer: register interpreters and execute foreign bytecode payloads.
\* Keeps single-node CoreMetaVM semantics and adds interpreter registry queues.

CONSTANTS Interpreters, ForeignPayloads, MaxQueueLen, MaxResultLen

ASSUME Interpreters # {}
ASSUME ForeignPayloads # {}
ASSUME MaxQueueLen \in Nat
ASSUME MaxResultLen \in Nat /\ MaxResultLen > 0

VARIABLES
  registry,
  foreignQueue,
  foreignResults

MetaVars == <<CoreVars, registry, foreignQueue, foreignResults>>
SeqElems(s) == {s[i] : i \in 1..Len(s)}

MetaInit ==
  /\ Init
  /\ registry = [i \in Interpreters |-> FALSE]
  /\ foreignQueue = <<>>
  /\ foreignResults = <<>>

RegisterInterpreter(i) ==
  /\ i \in Interpreters
  /\ registry[i] = FALSE
  /\ registry' = [registry EXCEPT ![i] = TRUE]
  /\ UNCHANGED <<CoreVars, foreignQueue, foreignResults>>

EnqueueExec(i, payload) ==
  /\ i \in Interpreters
  /\ payload \in ForeignPayloads
  /\ registry[i] = TRUE
  /\ Len(foreignQueue) < MaxQueueLen
  /\ foreignQueue' = Append(foreignQueue, [interpreter |-> i, payload |-> payload])
  /\ UNCHANGED <<CoreVars, registry, foreignResults>>

RunExec ==
  /\ Len(foreignQueue) > 0
  /\ LET req == Head(foreignQueue) IN
       /\ foreignQueue' = Tail(foreignQueue)
       /\ LET r == [interpreter |-> req.interpreter, status |-> "ok", output |-> req.payload] IN
            foreignResults' =
              IF Len(foreignResults) < MaxResultLen
              THEN Append(foreignResults, r)
              ELSE Append(Tail(foreignResults), r)
       /\ UNCHANGED <<CoreVars, registry>>

MetaNext ==
  \/ /\ CoreStep
     /\ UNCHANGED <<registry, foreignQueue, foreignResults>>
  \/ /\ OutOfBudget
     /\ UNCHANGED <<registry, foreignQueue, foreignResults>>
  \/ \E i \in Interpreters : RegisterInterpreter(i)
  \/ \E i \in Interpreters : \E p \in ForeignPayloads : EnqueueExec(i, p)
  \/ RunExec
  \/ /\ halted
     /\ UNCHANGED MetaVars

MetaTypeOK ==
  /\ TypeOK
  /\ registry \in [Interpreters -> BOOLEAN]
  /\ Len(foreignQueue) <= MaxQueueLen
  /\ Len(foreignResults) <= MaxResultLen
  /\ \A e \in SeqElems(foreignQueue) : e.interpreter \in Interpreters /\ e.payload \in ForeignPayloads
  /\ \A r \in SeqElems(foreignResults) : r.interpreter \in Interpreters /\ r.status \in {"ok"} /\ r.output \in ForeignPayloads

InterpreterReady(i) == i \in Interpreters /\ registry[i]

ExecInterpreterAllowed ==
  \A e \in SeqElems(foreignQueue) : InterpreterReady(e.interpreter)

MetaSpec == MetaInit /\ [][MetaNext]_MetaVars

THEOREM MetaSpec => []MetaTypeOK

=============================================================================
