---- MODULE StabilityBuggy ----
EXTENDS Integers
VARIABLES mode

Init == mode = "warm"

Flip ==
    \/ (mode = "warm" /\ mode' = "cold")
    \/ (mode = "cold" /\ mode' = "warm")

vars == <<mode>>
Spec == Init /\ [][Flip]_vars /\ WF_vars(Flip)

EventuallyAlwaysWarm == <>[](mode = "warm")
====
