---- MODULE DiningPhilosophers ----
EXTENDS Integers
VARIABLES pc, forks

Phils == 0..2
LeftFork(p) == p
RightFork(p) == (p + 1) % 3

TypeOK ==
    /\ pc \in [Phils -> {"thinking", "hasLeft", "eating"}]
    /\ forks \in [Phils -> {-1, 0, 1, 2}]

Init ==
    /\ pc = [p \in Phils |-> "thinking"]
    /\ forks = [f \in Phils |-> -1]

PickLeft(p) ==
    /\ pc[p] = "thinking"
    /\ forks[LeftFork(p)] = -1
    /\ forks' = [forks EXCEPT ![LeftFork(p)] = p]
    /\ pc' = [pc EXCEPT ![p] = "hasLeft"]

PickRight(p) ==
    /\ pc[p] = "hasLeft"
    /\ forks[RightFork(p)] = -1
    /\ forks' = [forks EXCEPT ![RightFork(p)] = p]
    /\ pc' = [pc EXCEPT ![p] = "eating"]

PutDown(p) ==
    /\ pc[p] = "eating"
    /\ forks' = [forks EXCEPT ![LeftFork(p)] = -1, ![RightFork(p)] = -1]
    /\ pc' = [pc EXCEPT ![p] = "thinking"]

Next ==
    \E p \in Phils :
        \/ PickLeft(p)
        \/ PickRight(p)
        \/ PutDown(p)

NoSharedFork ==
    \A p \in Phils :
        pc[p] = "eating" => (forks[LeftFork(p)] = p /\ forks[RightFork(p)] = p)
====
