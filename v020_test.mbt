///|
test "v020: RECURSIVE operator sum and factorial" {
  let tla =
    #|---- MODULE RecTest ----
    #|EXTENDS Integers, FiniteSets
    #|VARIABLE total
    #|RECURSIVE SumSet(_)
    #|SumSet(S) == IF S = {} THEN 0 ELSE LET x == CHOOSE y \in S : TRUE IN x + SumSet(S \ {x})
    #|Init == total = SumSet({1, 2, 3, 4})
    #|Next == total' = total
    #|Inv == total = 10
    #|====
  let cfg =
    #|INIT Init
    #|NEXT Next
    #|INVARIANT Inv
  let res = @moon-tla.check_spec_sources(tla, cfg)
  assert_eq(res.status, Ok)
  assert_eq(res.distinct_states, 1)
}

///|
test "v020: SYMMETRY Permutations quotient reduction" {
  let tla =
    #|---- MODULE SymTest ----
    #|EXTENDS TLC
    #|CONSTANT Nodes
    #|VARIABLE done
    #|Sym == Permutations(Nodes)
    #|Init == done = {}
    #|Next == \E n \in Nodes : n \notin done /\ done' = done \cup {n}
    #|Inv == done \subseteq Nodes
    #|====
  let cfg =
    #|INIT Init
    #|NEXT Next
    #|CONSTANT Nodes = {n1, n2, n3}
    #|SYMMETRY Sym
    #|INVARIANT Inv
    #|CHECK_DEADLOCK FALSE
  let res_sym = @moon-tla.check_spec_sources(tla, cfg)
  assert_eq(res_sym.status, Ok)
  assert_true(res_sym.symmetry_applied)
  // Subsets of 3 symmetric nodes have 4 equivalence classes by cardinality: 0, 1, 2, 3
  assert_eq(res_sym.distinct_states, 4)

  let res_nosym = @moon-tla.check_spec_sources(
    tla,
    cfg,
    options=@moon-tla.check_options(use_symmetry=false),
  )
  assert_eq(res_nosym.status, Ok)
  assert_true(!res_nosym.symmetry_applied)
  assert_eq(res_nosym.distinct_states, 8)
}

///|
test "v020: per-action WF vs SF Emerson-Lei fairness distinction" {
  // Classic WF vs SF example:
  // x toggles 0 <-> 1 via Toggle; Finish (0 -> 2) is enabled ONLY when x = 0.
  // Under WF_x(Finish), Finish is NOT continuously enabled (disabled at x=1), so 0<->1 violates <>Done!
  // Under SF_x(Finish), Finish IS infinitely often enabled along 0<->1, so 0<->1 is pruned and <>Done HOLDS!
  let tla_wf =
    #|---- MODULE WfVsSf ----
    #|VARIABLE x
    #|Init == x = 0
    #|Toggle == (x = 0 /\ x' = 1) \/ (x = 1 /\ x' = 0)
    #|Finish == x = 0 /\ x' = 2
    #|Stay == x = 2 /\ x' = 2
    #|Next == Toggle \/ Finish \/ Stay
    #|SpecWF == Init /\ [][Next]_x /\ WF_x(Toggle) /\ WF_x(Finish)
    #|SpecSF == Init /\ [][Next]_x /\ WF_x(Toggle) /\ SF_x(Finish)
    #|EventuallyDone == <>(x = 2)
    #|====
  let cfg_wf =
    #|SPECIFICATION SpecWF
    #|PROPERTY EventuallyDone
  let cfg_sf =
    #|SPECIFICATION SpecSF
    #|PROPERTY EventuallyDone

  let res_wf = @moon-tla.check_spec_sources(tla_wf, cfg_wf)
  assert_eq(res_wf.status, LivenessViolation("EventuallyDone"))
  assert_true(res_wf.lasso_loop_start is Some(_))

  let res_sf = @moon-tla.check_spec_sources(tla_wf, cfg_sf)
  assert_eq(res_sf.status, Ok)
}
