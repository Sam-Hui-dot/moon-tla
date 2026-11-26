---- MODULE MutexPeterson ----
EXTENDS Integers
VARIABLES pc, flag, turn

Procs == {0, 1}
Other(i) == 1 - i

TypeOK ==
    /\ pc \in [Procs -> {"idle", "setTurn", "wait", "cs", "exit"}]
    /\ flag \in [Procs -> BOOLEAN]
    /\ turn \in Procs

Init ==
    /\ pc = [i \in Procs |-> "idle"]
    /\ flag = [i \in Procs |-> FALSE]
    /\ turn = 0

SetFlag(i) ==
    /\ pc[i] = "idle"
    /\ flag' = [flag EXCEPT ![i] = TRUE]
    /\ pc' = [pc EXCEPT ![i] = "setTurn"]
    /\ UNCHANGED turn

SetTurn(i) ==
    /\ pc[i] = "setTurn"
    /\ turn' = Other(i)
    /\ pc' = [pc EXCEPT ![i] = "wait"]
    /\ UNCHANGED flag

EnterCS(i) ==
    /\ pc[i] = "wait"
    /\ (~flag[Other(i)] \/ turn = i)
    /\ pc' = [pc EXCEPT ![i] = "cs"]
    /\ UNCHANGED <<flag, turn>>

LeaveCS(i) ==
    /\ pc[i] = "cs"
    /\ pc' = [pc EXCEPT ![i] = "exit"]
    /\ UNCHANGED <<flag, turn>>

ClearFlag(i) ==
    /\ pc[i] = "exit"
    /\ flag' = [flag EXCEPT ![i] = FALSE]
    /\ pc' = [pc EXCEPT ![i] = "idle"]
    /\ UNCHANGED turn

Next ==
    \E i \in Procs :
        \/ SetFlag(i)
        \/ SetTurn(i)
        \/ EnterCS(i)
        \/ LeaveCS(i)
        \/ ClearFlag(i)

MutualExclusion == ~(pc[0] = "cs" /\ pc[1] = "cs")
====
