---- MODULE TokenRingLiveness ----
EXTENDS Integers
VARIABLE holder

Nodes == 0..3

TypeOK == holder \in Nodes

Init == holder = 0

PassToken == holder' = (holder + 1) % 4

Next == PassToken

Spec == Init /\ [][Next]_holder /\ WF_holder(Next)

AllNodesServed == \A n \in Nodes : []<>(holder = n)
====
