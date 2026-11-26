---- MODULE TokenRing ----
EXTENDS Integers, FiniteSets
VARIABLES hasToken, inCS

Nodes == 0..3

TypeOK ==
    /\ hasToken \in [Nodes -> BOOLEAN]
    /\ inCS \in [Nodes -> BOOLEAN]

Init ==
    /\ hasToken = [n \in Nodes |-> n = 0]
    /\ inCS = [n \in Nodes |-> FALSE]

EnterCS(n) ==
    /\ hasToken[n]
    /\ ~inCS[n]
    /\ inCS' = [inCS EXCEPT ![n] = TRUE]
    /\ UNCHANGED hasToken

ExitCS(n) ==
    /\ inCS[n]
    /\ inCS' = [inCS EXCEPT ![n] = FALSE]
    /\ UNCHANGED hasToken

PassToken(n) ==
    /\ hasToken[n]
    /\ ~inCS[n]
    /\ hasToken' = [hasToken EXCEPT ![n] = FALSE, ![(n + 1) % 4] = TRUE]
    /\ UNCHANGED inCS

Next ==
    \E n \in Nodes :
        \/ EnterCS(n)
        \/ ExitCS(n)
        \/ PassToken(n)

SingleToken ==
    Cardinality({n \in Nodes : hasToken[n]}) = 1

MutualExclusion ==
    \A a, b \in Nodes : (inCS[a] /\ inCS[b]) => a = b
====
