---- MODULE ChandyLamport ----
EXTENDS Integers
VARIABLES balA, balB, inFlight, snapA, snapB, snapChan

Init ==
    /\ balA = 2
    /\ balB = 2
    /\ inFlight = 0
    /\ snapA = -1
    /\ snapB = -1
    /\ snapChan = -1

SendFromA ==
    /\ balA > 0
    /\ balA' = balA - 1
    /\ inFlight' = inFlight + 1
    /\ UNCHANGED <<balB, snapA, snapB, snapChan>>

DeliverToB ==
    /\ inFlight > 0
    /\ inFlight' = inFlight - 1
    /\ balB' = balB + 1
    /\ UNCHANGED <<balA, snapA, snapB, snapChan>>

TakeSnapA ==
    /\ snapA = -1
    /\ snapA' = balA
    /\ snapChan' = inFlight
    /\ UNCHANGED <<balA, balB, inFlight, snapB>>

TakeSnapB ==
    /\ snapA /= -1
    /\ snapB = -1
    /\ inFlight = snapChan
    /\ snapB' = balB
    /\ UNCHANGED <<balA, balB, inFlight, snapA, snapChan>>

Next ==
    \/ SendFromA
    \/ DeliverToB
    \/ TakeSnapA
    \/ TakeSnapB
    \/ (snapB /= -1 /\ UNCHANGED <<balA, balB, inFlight, snapA, snapB, snapChan>>)

Conservation == balA + balB + inFlight = 4
SnapshotConsistent == (snapA /= -1 /\ snapB /= -1) => (snapA + snapB + snapChan = 4)
====
