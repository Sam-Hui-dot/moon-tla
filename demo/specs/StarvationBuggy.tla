---- MODULE StarvationBuggy ----
EXTENDS Integers
VARIABLES pc, lock

vars == <<pc, lock>>
Procs == {0, 1}

TypeOK ==
    /\ pc \in [Procs -> {"idle", "wait", "cs"}]
    /\ lock \in {0, 1}

Init ==
    /\ pc = [i \in Procs |-> "idle"]
    /\ lock = 0

Request(i) ==
    /\ pc[i] = "idle"
    /\ pc' = [pc EXCEPT ![i] = "wait"]
    /\ UNCHANGED lock

Enter0 ==
    /\ pc[0] = "wait"
    /\ lock = 0
    /\ lock' = 1
    /\ pc' = [pc EXCEPT ![0] = "cs"]

Enter1 ==
    /\ pc[1] = "wait"
    /\ lock = 0
    /\ pc[0] = "idle"
    /\ lock' = 1
    /\ pc' = [pc EXCEPT ![1] = "cs"]

Leave(i) ==
    /\ pc[i] = "cs"
    /\ lock' = 0
    /\ pc' = [pc EXCEPT ![i] = "idle"]

ProcStep(i) ==
    \/ Request(i)
    \/ (IF i = 0 THEN Enter0 ELSE Enter1)
    \/ Leave(i)

Next == \E i \in Procs : ProcStep(i)

Spec == Init /\ [][Next]_vars /\ \A i \in Procs : WF_vars(ProcStep(i))

MutualExclusion == ~(pc[0] = "cs" /\ pc[1] = "cs")

StarvationFree == (pc[1] = "wait") ~> (pc[1] = "cs")
====
