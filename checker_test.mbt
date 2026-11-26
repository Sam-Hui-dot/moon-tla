///|
test "diehard finds exact shortest 6-step solution trace" {
  let tla =
    #|---- MODULE DieHard ----
    #|EXTENDS Integers
    #|VARIABLES small, big
    #|
    #|TypeOK == /\ small \in 0..3
    #|          /\ big \in 0..5
    #|
    #|Init == /\ small = 0
    #|        /\ big = 0
    #|
    #|FillSmall == /\ small' = 3
    #|             /\ big' = big
    #|
    #|FillBig == /\ big' = 5
    #|           /\ small' = small
    #|
    #|EmptySmall == /\ small' = 0
    #|              /\ big' = big
    #|
    #|EmptyBig == /\ big' = 0
    #|            /\ small' = small
    #|
    #|SmallToBig ==
    #|    LET poured == IF small + big <= 5 THEN small ELSE 5 - big
    #|    IN  /\ small' = small - poured
    #|        /\ big' = big + poured
    #|
    #|BigToSmall ==
    #|    LET poured == IF small + big <= 3 THEN big ELSE 3 - small
    #|    IN  /\ small' = small + poured
    #|        /\ big' = big - poured
    #|
    #|Next ==
    #|    \/ FillSmall
    #|    \/ FillBig
    #|    \/ EmptySmall
    #|    \/ EmptyBig
    #|    \/ SmallToBig
    #|    \/ BigToSmall
    #|
    #|NotSolved == big # 4
    #|====
  let cfg =
    #|INIT Init
    #|NEXT Next
    #|INVARIANTS TypeOK NotSolved
  let res = @moon-tla.check_spec_sources(tla, cfg)
  assert_eq(res.status, InvariantViolation("NotSolved"))
  // Shortest DieHard solution takes 6 transitions => 7 trace states
  assert_eq(res.trace.length(), 7)
  let last = res.trace[res.trace.length() - 1]
  let mut big_val = ""
  for b in last.bindings {
    if b.name == "big" {
      big_val = b.value
    }
  }
  assert_eq(big_val, "4")
}

///|
test "diehard full state space without NotSolved has exact 16 distinct states" {
  let tla =
    #|---- MODULE DieHardFull ----
    #|EXTENDS Integers
    #|VARIABLES small, big
    #|TypeOK == small \in 0..3 /\ big \in 0..5
    #|Init == small = 0 /\ big = 0
    #|FillSmall == small' = 3 /\ big' = big
    #|FillBig == big' = 5 /\ small' = small
    #|EmptySmall == small' = 0 /\ big' = big
    #|EmptyBig == big' = 0 /\ small' = small
    #|SmallToBig ==
    #|    LET p == IF small + big <= 5 THEN small ELSE 5 - big
    #|    IN small' = small - p /\ big' = big + p
    #|BigToSmall ==
    #|    LET p == IF small + big <= 3 THEN big ELSE 3 - small
    #|    IN small' = small + p /\ big' = big - p
    #|Next == FillSmall \/ FillBig \/ EmptySmall \/ EmptyBig \/ SmallToBig \/ BigToSmall
    #|====
  let cfg =
    #|INIT Init
    #|NEXT Next
    #|INVARIANT TypeOK
  let res = @moon-tla.check_spec_sources(tla, cfg)
  assert_eq(res.status, Ok)
  assert_eq(res.distinct_states, 16)
  assert_eq(res.diameter, 8)
}

///|
test "deadlock detection and liveness tarjan scc lasso trace" {
  let deadlock_tla =
    #|---- MODULE Stuck ----
    #|EXTENDS Integers
    #|VARIABLE x
    #|Init == x = 0
    #|Next == x < 2 /\ x' = x + 1
    #|====
  let res_dl = @moon-tla.check_spec_sources(
    deadlock_tla, "INIT Init\nNEXT Next",
  )
  assert_eq(res_dl.status, Deadlock)
  assert_eq(res_dl.trace.length(), 3)

  // Liveness: cyclic counter without reaching 3 fails <>Reached3 with a lasso trace
  let live_fail_tla =
    #|---- MODULE CycleFail ----
    #|EXTENDS Integers
    #|VARIABLE x
    #|Init == x = 0
    #|Step == x' = (x + 1) % 2
    #|Next == Step
    #|Spec == Init /\ [][Next]_x /\ WF_x(Next)
    #|Reached3 == <>(x = 3)
    #|====
  let res_lf = @moon-tla.check_spec_sources(
    live_fail_tla, "SPECIFICATION Spec\nPROPERTY Reached3",
  )
  assert_eq(res_lf.status, LivenessViolation("Reached3"))
  assert_true(res_lf.lasso_loop_start is Some(_))
  assert_true(res_lf.trace.length() >= 3)

  // Liveness: cyclic counter 0 -> 1 -> 0 satisfies (x = 0) ~> (x = 1) under WF_x(Next)
  let live_ok_tla =
    #|---- MODULE CycleOk ----
    #|EXTENDS Integers
    #|VARIABLE x
    #|Init == x = 0
    #|Step == x' = (x + 1) % 2
    #|Next == Step
    #|Spec == Init /\ [][Next]_x /\ WF_x(Next)
    #|ZeroLeadsToOne == (x = 0) ~> (x = 1)
    #|====
  let res_lo = @moon-tla.check_spec_sources(
    live_ok_tla, "SPECIFICATION Spec\nPROPERTY ZeroLeadsToOne",
  )
  assert_eq(res_lo.status, Ok)
}
