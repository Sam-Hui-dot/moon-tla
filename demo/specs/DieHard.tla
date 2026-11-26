---- MODULE DieHard ----
EXTENDS Integers
VARIABLES small, big

TypeOK ==
    /\ small \in 0..3
    /\ big \in 0..5

Init ==
    /\ small = 0
    /\ big = 0

FillSmall ==
    /\ small' = 3
    /\ big' = big

FillBig ==
    /\ big' = 5
    /\ small' = small

EmptySmall ==
    /\ small' = 0
    /\ big' = big

EmptyBig ==
    /\ big' = 0
    /\ small' = small

SmallToBig ==
    LET poured == IF small + big <= 5 THEN small ELSE 5 - big
    IN  /\ small' = small - poured
        /\ big' = big + poured

BigToSmall ==
    LET poured == IF small + big <= 3 THEN big ELSE 3 - small
    IN  /\ small' = small + poured
        /\ big' = big - poured

Next ==
    \/ FillSmall
    \/ FillBig
    \/ EmptySmall
    \/ EmptyBig
    \/ SmallToBig
    \/ BigToSmall

NotSolved == big # 4
====
