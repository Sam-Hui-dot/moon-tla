---- MODULE SlidingWindow ----
EXTENDS Integers
CONSTANTS MaxMsg
VARIABLES sent, acked, inFlight

Init ==
    /\ sent = 0
    /\ acked = 0
    /\ inFlight = {}

SendNext ==
    /\ sent < MaxMsg
    /\ sent - acked < 2
    /\ sent' = sent + 1
    /\ inFlight' = inFlight \cup {sent + 1}
    /\ UNCHANGED acked

DeliverAck ==
    /\ (acked + 1) \in inFlight
    /\ acked' = acked + 1
    /\ inFlight' = inFlight \ {acked + 1}
    /\ UNCHANGED sent

Next ==
    \/ SendNext
    \/ DeliverAck
    \/ (acked = MaxMsg /\ UNCHANGED <<sent, acked, inFlight>>)

vars == <<sent, acked, inFlight>>
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

WindowBound == sent - acked <= 2 /\ acked <= sent
AllDelivered == <>[](acked = MaxMsg)
====
