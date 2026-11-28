---- MODULE PaxosSym ----
EXTENDS Integers, FiniteSets, TLC
CONSTANTS Acceptor, Value, Quorum
VARIABLES maxBal, maxVBal, maxVal, msgs

Sym == Permutations(Acceptor)
Ballot == 0..1
None == "none"

TypeOK ==
    /\ maxBal \in [Acceptor -> Ballot \cup {-1}]
    /\ maxVBal \in [Acceptor -> Ballot \cup {-1}]
    /\ maxVal \in [Acceptor -> Value \cup {None}]

Init ==
    /\ maxBal = [a \in Acceptor |-> -1]
    /\ maxVBal = [a \in Acceptor |-> -1]
    /\ maxVal = [a \in Acceptor |-> None]
    /\ msgs = {}

Send(m) == msgs' = msgs \cup {m}

Phase1a(b) ==
    /\ ~(\E m \in msgs : m.type = "1a" /\ m.bal = b)
    /\ Send([type |-> "1a", bal |-> b])
    /\ UNCHANGED <<maxBal, maxVBal, maxVal>>

Phase1b(a) ==
    \E m \in msgs :
        /\ m.type = "1a"
        /\ m.bal > maxBal[a]
        /\ maxBal' = [maxBal EXCEPT ![a] = m.bal]
        /\ Send([type |-> "1b", acc |-> a, bal |-> m.bal,
                 mbal |-> maxVBal[a], mval |-> maxVal[a]])
        /\ UNCHANGED <<maxVBal, maxVal>>

Phase2a(b, v) ==
    /\ ~(\E m \in msgs : m.type = "2a" /\ m.bal = b)
    /\ \E Q \in Quorum :
        LET Q1b == {m \in msgs : m.type = "1b" /\ m.acc \in Q /\ m.bal = b}
            Q1bv == {m \in Q1b : m.mbal >= 0}
        IN /\ \A a \in Q : \E m \in Q1b : m.acc = a
           /\ \/ Q1bv = {}
              \/ \E m \in Q1bv :
                    /\ m.mval = v
                    /\ \A m2 \in Q1bv : m.mbal >= m2.mbal
    /\ Send([type |-> "2a", bal |-> b, val |-> v])
    /\ UNCHANGED <<maxBal, maxVBal, maxVal>>

Phase2b(a) ==
    \E m \in msgs :
        /\ m.type = "2a"
        /\ m.bal >= maxBal[a]
        /\ maxBal' = [maxBal EXCEPT ![a] = m.bal]
        /\ maxVBal' = [maxVBal EXCEPT ![a] = m.bal]
        /\ maxVal' = [maxVal EXCEPT ![a] = m.val]
        /\ Send([type |-> "2b", acc |-> a, bal |-> m.bal, val |-> m.val])

Next ==
    \/ \E b \in Ballot : Phase1a(b)
    \/ \E b \in Ballot : \E v \in Value : Phase2a(b, v)
    \/ \E a \in Acceptor : Phase1b(a) \/ Phase2b(a)

ChosenAt(b, v) ==
    \E Q \in Quorum :
        \A a \in Q : [type |-> "2b", acc |-> a, bal |-> b, val |-> v] \in msgs

Chosen == {v \in Value : \E b \in Ballot : ChosenAt(b, v)}

Agreement == Cardinality(Chosen) <= 1
====
