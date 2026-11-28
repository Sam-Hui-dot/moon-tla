---- MODULE BagsDemo ----
EXTENDS Integers, Bags
VARIABLES bag, done

Items == {"a", "b"}

Init ==
    /\ bag = SetToBag(Items)
    /\ done = 0

Consume(x) ==
    /\ BagIn(x, bag)
    /\ LET c == CopiesIn(x, bag)
       IN bag' = IF c > 1
                 THEN [bag EXCEPT ![x] = c - 1]
                 ELSE [k \in (BagToSet(bag) \ {x}) |-> CopiesIn(k, bag)]
    /\ done' = done + 1

Next ==
    \/ \E x \in Items : Consume(x)
    \/ (bag = EmptyBag /\ UNCHANGED <<bag, done>>)

vars == <<bag, done>>
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

BagValid == IsABag(bag)
Conservation == BagCardinality(bag) + done = 2
EventuallyEmpty == <>[](bag = EmptyBag)
====
