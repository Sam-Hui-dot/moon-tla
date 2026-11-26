---- MODULE BankTransferBuggy ----
EXTENDS Integers
VARIABLES alice, bob, pc

Txs == {1, 2}
Amount == 6

TypeOK ==
    /\ alice \in Int
    /\ bob \in Int
    /\ pc \in [Txs -> {"ready", "checked", "debited", "done", "declined"}]

Init ==
    /\ alice = 10
    /\ bob = 10
    /\ pc = [t \in Txs |-> "ready"]

\* INJECTED BUG: check balance and debit occur in separate atomic steps (TOCTOU race)
CheckBalance(t) ==
    /\ pc[t] = "ready"
    /\ IF alice >= Amount
       THEN pc' = [pc EXCEPT ![t] = "checked"]
       ELSE pc' = [pc EXCEPT ![t] = "declined"]
    /\ UNCHANGED <<alice, bob>>

DebitAlice(t) ==
    /\ pc[t] = "checked"
    /\ alice' = alice - Amount
    /\ pc' = [pc EXCEPT ![t] = "debited"]
    /\ UNCHANGED bob

CreditBob(t) ==
    /\ pc[t] = "debited"
    /\ bob' = bob + Amount
    /\ pc' = [pc EXCEPT ![t] = "done"]
    /\ UNCHANGED alice

Next ==
    \E t \in Txs :
        \/ CheckBalance(t)
        \/ DebitAlice(t)
        \/ CreditBob(t)

NoOverdraft == alice >= 0 /\ bob >= 0
====
