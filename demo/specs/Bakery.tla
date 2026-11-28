---- MODULE Bakery ----
EXTENDS Integers
CONSTANTS MaxTicket
VARIABLES pc, num, choosing

Procs == {1, 2}

Init ==
    /\ pc = [p \in Procs |-> "idle"]
    /\ num = [p \in Procs |-> 0]
    /\ choosing = [p \in Procs |-> FALSE]

StartChoose(p) ==
    /\ pc[p] = "idle"
    /\ choosing' = [choosing EXCEPT ![p] = TRUE]
    /\ pc' = [pc EXCEPT ![p] = "choose"]
    /\ UNCHANGED num

PickTicket(p) ==
    /\ pc[p] = "choose"
    /\ LET other == IF p = 1 THEN 2 ELSE 1
           nextNum == num[other] + 1
       IN /\ nextNum <= MaxTicket
          /\ num' = [num EXCEPT ![p] = nextNum]
          /\ choosing' = [choosing EXCEPT ![p] = FALSE]
          /\ pc' = [pc EXCEPT ![p] = "wait"]

EnterCS(p) ==
    /\ pc[p] = "wait"
    /\ LET other == IF p = 1 THEN 2 ELSE 1
       IN /\ ~choosing[other]
          /\ (num[other] = 0 \/ num[p] < num[other] \/ (num[p] = num[other] /\ p < other))
    /\ pc' = [pc EXCEPT ![p] = "cs"]
    /\ UNCHANGED <<num, choosing>>

ExitCS(p) ==
    /\ pc[p] = "cs"
    /\ num' = [num EXCEPT ![p] = 0]
    /\ pc' = [pc EXCEPT ![p] = "idle"]
    /\ UNCHANGED choosing

Next == \E p \in Procs : StartChoose(p) \/ PickTicket(p) \/ EnterCS(p) \/ ExitCS(p)

MutualExclusion == ~(pc[1] = "cs" /\ pc[2] = "cs")
====
