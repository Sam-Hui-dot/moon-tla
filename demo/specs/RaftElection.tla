---- MODULE RaftElection ----
EXTENDS Integers, FiniteSets
CONSTANTS Servers, MaxTerm, Nil
VARIABLES currentTerm, state, votedFor, votesGranted

vars == <<currentTerm, state, votedFor, votesGranted>>

TypeOK ==
    /\ currentTerm \in [Servers -> 0..MaxTerm]
    /\ state \in [Servers -> {"follower", "candidate", "leader"}]
    /\ votedFor \in [Servers -> Servers \cup {Nil}]
    /\ votesGranted \in [Servers -> SUBSET Servers]

Init ==
    /\ currentTerm = [s \in Servers |-> 0]
    /\ state = [s \in Servers |-> "follower"]
    /\ votedFor = [s \in Servers |-> Nil]
    /\ votesGranted = [s \in Servers |-> {}]

Timeout(i) ==
    /\ state[i] \in {"follower", "candidate"}
    /\ currentTerm[i] < MaxTerm
    /\ currentTerm' = [currentTerm EXCEPT ![i] = @ + 1]
    /\ state' = [state EXCEPT ![i] = "candidate"]
    /\ votedFor' = [votedFor EXCEPT ![i] = i]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {i}]

GrantVote(voter, cand) ==
    /\ voter # cand
    /\ state[cand] = "candidate"
    /\ voter \notin votesGranted[cand]
    /\ currentTerm[cand] >= currentTerm[voter]
    /\ (currentTerm[cand] > currentTerm[voter] \/ votedFor[voter] \in {Nil, cand})
    /\ currentTerm' = [currentTerm EXCEPT ![voter] = currentTerm[cand]]
    /\ votedFor' = [votedFor EXCEPT ![voter] = cand]
    /\ state' = IF currentTerm[cand] > currentTerm[voter]
                THEN [state EXCEPT ![voter] = "follower"]
                ELSE state
    /\ votesGranted' =
        IF currentTerm[cand] > currentTerm[voter]
        THEN [votesGranted EXCEPT ![voter] = {}, ![cand] = @ \cup {voter}]
        ELSE [votesGranted EXCEPT ![cand] = @ \cup {voter}]

BecomeLeader(i) ==
    /\ state[i] = "candidate"
    /\ Cardinality(votesGranted[i]) * 2 > Cardinality(Servers)
    /\ state' = [state EXCEPT ![i] = "leader"]
    /\ UNCHANGED <<currentTerm, votedFor, votesGranted>>

Idle ==
    /\ UNCHANGED vars

Next ==
    \/ \E i \in Servers : Timeout(i)
    \/ \E v \in Servers : \E c \in Servers : GrantVote(v, c)
    \/ \E i \in Servers : BecomeLeader(i)
    \/ Idle

ElectionSafety ==
    \A i, j \in Servers :
        (state[i] = "leader" /\ state[j] = "leader" /\ currentTerm[i] = currentTerm[j]) => i = j
====
