---- MODULE MutexBuggy ----
EXTENDS Integers
VARIABLES pc, flag

Procs == {0, 1}
Other(i) == 1 - i

TypeOK ==
    /\ pc \in [Procs -> {"idle", "checked", "cs"}]
    /\ flag \in [Procs -> BOOLEAN]

Init ==
    /\ pc = [i \in Procs |-> "idle"]
    /\ flag = [i \in Procs |-> FALSE]

\* INJECTED BUG: checks peer flag before raising own flag (TOCTOU race)
CheckPeer(i) ==
    /\ pc[i] = "idle"
    /\ ~flag[Other(i)]
    /\ pc' = [pc EXCEPT ![i] = "checked"]
    /\ UNCHANGED flag

RaiseAndEnter(i) ==
    /\ pc[i] = "checked"
    /\ flag' = [flag EXCEPT ![i] = TRUE]
    /\ pc' = [pc EXCEPT ![i] = "cs"]

LeaveCS(i) ==
    /\ pc[i] = "cs"
    /\ flag' = [flag EXCEPT ![i] = FALSE]
    /\ pc' = [pc EXCEPT ![i] = "idle"]

Next ==
    \E i \in Procs :
        \/ CheckPeer(i)
        \/ RaiseAndEnter(i)
        \/ LeaveCS(i)

MutualExclusion == ~(pc[0] = "cs" /\ pc[1] = "cs")
====
