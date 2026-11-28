///|
test "v0.3.0 eventual stability <>[]P passes on EWD840 and fails with lasso on StabilityBuggy" {
  let ok_src =
    #|---- MODULE EwdMini ----
    #|EXTENDS Integers
    #|VARIABLES x
    #|Init == x = 0
    #|Next == (x < 2 /\ x' = x + 1) \/ (x = 2 /\ x' = 2)
    #|vars == <<x>>
    #|Spec == Init /\ [][Next]_vars /\ WF_vars(Next)
    #|Stable == <>[](x = 2)
    #|====
  let ok_cfg = "SPECIFICATION Spec\nPROPERTY Stable\nCHECK_DEADLOCK FALSE\n"
  let r_ok = @moon-tla.check_spec_sources(ok_src, ok_cfg)
  assert_eq(r_ok.status, Ok)
  assert_eq(r_ok.distinct_states, 3)

  let bad_src =
    #|---- MODULE FlipMini ----
    #|VARIABLES m
    #|Init == m = 0
    #|Next == (m = 0 /\ m' = 1) \/ (m = 1 /\ m' = 0)
    #|vars == <<m>>
    #|Spec == Init /\ [][Next]_vars /\ WF_vars(Next)
    #|AlwaysEventuallyZero == <>[](m = 0)
    #|====
  let bad_cfg = "SPECIFICATION Spec\nPROPERTY AlwaysEventuallyZero\nCHECK_DEADLOCK FALSE\n"
  let r_bad = @moon-tla.check_spec_sources(bad_src, bad_cfg)
  assert_eq(r_bad.status, LivenessViolation("AlwaysEventuallyZero"))
  assert_true(r_bad.lasso_loop_start is Some(_))
}

///|
test "v0.3.0 Bags standard module operators" {
  let src =
    #|---- MODULE BagsUnit ----
    #|EXTENDS Integers, Bags
    #|VARIABLES b
    #|Init == b = SetToBag({"x", "y"})
    #|Next == b' = EmptyBag
    #|Inv == IsABag(b) /\ (b = EmptyBag \/ (BagIn("x", b) /\ CopiesIn("x", b) = 1 /\ BagCardinality(b) = 2 /\ SubBag(EmptyBag, b)))
    #|====
  let cfg = "INIT Init\nNEXT Next\nINVARIANT Inv\nCHECK_DEADLOCK FALSE\n"
  let r = @moon-tla.check_spec_sources(src, cfg)
  assert_eq(r.status, Ok)
  assert_eq(r.distinct_states, 2)
}

///|
test "v0.3.0 persistence-to-recurrence <>[]P => []<>Q liveness" {
  let src =
    #|---- MODULE PersistRec ----
    #|VARIABLES p, q
    #|Init == p = TRUE /\ q = FALSE
    #|Next == p' = TRUE /\ q' = FALSE
    #|vars == <<p, q>>
    #|Spec == Init /\ [][Next]_vars /\ WF_vars(Next)
    #|Prop == (<>[](p = TRUE)) => ([]<>(q = TRUE))
    #|====
  let cfg = "SPECIFICATION Spec\nPROPERTY Prop\nCHECK_DEADLOCK FALSE\n"
  let r = @moon-tla.check_spec_sources(src, cfg)
  assert_eq(r.status, LivenessViolation("Prop"))
}
