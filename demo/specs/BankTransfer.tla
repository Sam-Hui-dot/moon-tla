---- MODULE BankTransfer ----
EXTENDS Integers
VARIABLES alice, bob, pc

Txs == {1, 2}
Amount == 6

TypeOK ==
    /\ alice \in Int
    /\ bob \in Int
    /\ pc \in [Txs -> {"ready", "done", "declined"}]

Init ==
    /\ alice = 10
    /\ bob = 10
    /\ pc = [t \in Txs |-> "ready"]

ExecuteTransfer(t) ==
    /\ pc[t] = "ready"
    /\ alice >= Amount
    /\ alice' = alice - Amount
    /\ bob' = bob + Amount
    /\ pc' = [pc EXCEPT ![t] = "done"]

DeclineTransfer(t) ==
    /\ pc[t] = "ready"
    /\ alice < Amount
    /\ pc' = [pc EXCEPT ![t] = "declined"]
    /\ UNCHANGED <<alice, bob>>

Next ==
    \E t \in Txs :
        \/ ExecuteTransfer(t)
        \/ DeclineTransfer(t)

TotalConserved == alice + bob = 20
NoOverdraft == alice >= 0 /\ bob >= 0
====
