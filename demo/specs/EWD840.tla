---- MODULE EWD840 ----
EXTENDS Integers
CONSTANTS N
VARIABLES active, color, tpos, tcolor

Nodes == 0..(N - 1)
Color == {"white", "black"}

Init ==
    /\ active = [i \in Nodes |-> TRUE]
    /\ color = [i \in Nodes |-> "white"]
    /\ tpos = 0
    /\ tcolor = "black"

Deactivate(i) ==
    /\ active[i]
    /\ active' = [active EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<color, tpos, tcolor>>

InitiateProbe ==
    /\ tpos = 0
    /\ \/ tcolor = "black"
       \/ color[0] = "black"
    /\ tpos' = N - 1
    /\ tcolor' = "white"
    /\ color' = [color EXCEPT ![0] = "white"]
    /\ UNCHANGED active

PassToken(i) ==
    /\ tpos = i
    /\ i > 0
    /\ ~active[i]
    /\ tpos' = i - 1
    /\ tcolor' = IF color[i] = "black" THEN "black" ELSE tcolor
    /\ color' = [color EXCEPT ![i] = "white"]
    /\ UNCHANGED active

Terminated == \A i \in Nodes : ~active[i]
TerminationDetected == tpos = 0 /\ tcolor = "white" /\ color[0] = "white" /\ ~active[0]

Next ==
    \/ InitiateProbe
    \/ \E i \in Nodes : Deactivate(i) \/ PassToken(i)
    \/ (TerminationDetected /\ UNCHANGED <<active, color, tpos, tcolor>>)

vars == <<active, color, tpos, tcolor>>
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

Safety == TerminationDetected => Terminated
EventualDetection == <>[]TerminationDetected
====
