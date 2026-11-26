///|
test "parse diehard module with bullet lists and comments" {
  let src =
    #|Leading prose before module header should be ignored.
    #|---- MODULE DieHard ----
    #|EXTENDS Integers
    #|VARIABLES small, big
    #|
    #|(* Nested (* block *) comment *)
    #|TypeOK == /\ small \in 0..3
    #|          /\ big \in 0..5
    #|
    #|Init ==
    #|    /\ small = 0
    #|    /\ big = 0
    #|
    #|FillSmall == /\ small' = 3
    #|             /\ big' = big
    #|
    #|SmallToBig ==
    #|    LET poured == IF small + big <= 5 THEN small ELSE 5 - big
    #|    IN  /\ small' = small - poured
    #|        /\ big' = big + poured
    #|
    #|Next ==
    #|    \/ FillSmall
    #|    \/ SmallToBig
    #|    \/ UNCHANGED <<small, big>>
    #|
    #|Spec == Init /\ [][Next]_<<small, big>> /\ WF_<<small, big>>(Next)
    #|====
    #|Trailing text after module footer.
  let m = @moon-tla.parse_module(src)
  assert_eq(m.name, "DieHard")
  assert_eq(m.extends, ["Integers"])
  assert_eq(m.variables, ["small", "big"])
  assert_eq(m.defs.length(), 6)
  assert_true(m.find_def("SmallToBig") is Some(_))
  assert_true(m.find_def("Spec") is Some(_))
}

///|
test "parse functions records except quantifiers and sets" {
  let e1 = @moon-tla.parse_expr_str(
    "[f EXCEPT ![a, b].count = @ + 1, ![c] = 0]",
  )
  assert_true(e1 is Except(_, clauses) && clauses.length() == 2)

  let e2 = @moon-tla.parse_expr_str(
    "[r \\in RM |-> [state |-> \"working\", term |-> 0]]",
  )
  assert_true(e2 is FuncDef(_, RecordLit(_)))

  let e3 = @moon-tla.parse_expr_str("{x \\in 1..10 : x % 2 = 0}")
  assert_true(e3 is SetFilter(Single("x"), _, _))

  let e4 = @moon-tla.parse_expr_str("{x * 2 : x \\in 1..5}")
  assert_true(e4 is SetMap(_, _))

  let e5 = @moon-tla.parse_expr_str(
    "\\A r1, r2 \\in RM : r1 # r2 => ~(s[r1] = \"c\" /\\ s[r2] = \"a\")",
  )
  assert_true(e5 is ForAll(_, Bin(Implies, _, _)))

  let e6 = @moon-tla.parse_expr_str(
    "CASE x = 1 -> 10 [] x = 2 -> 20 [] OTHER -> 30",
  )
  assert_true(e6 is CaseExpr(arms, Some(_)) && arms.length() == 2)

  let e7 = @moon-tla.parse_expr_str("CHOOSE x \\in S : x > 0")
  assert_true(e7 is Choose(Single("x"), _, _))

  let e8 = @moon-tla.parse_expr_str("(a :> 1) @@ (b :> 2)")
  assert_true(e8 is Bin(MergeFunc, Bin(MapTo, _, _), Bin(MapTo, _, _)))
}

///|
test "parse standard tlc cfg file" {
  let cfg_src =
    #|\* TLC config
    #|SPECIFICATION Spec
    #|CONSTANTS
    #|  RM = {r1, r2, r3}
    #|  MaxTerm = 2
    #|  Flag = TRUE
    #|  Empty = {}
    #|INVARIANT TypeOK
    #|INVARIANTS
    #|  TCConsistent
    #|  Safety
    #|PROPERTY EventuallyDone
    #|CHECK_DEADLOCK FALSE
  let cfg = @moon-tla.parse_cfg(cfg_src)
  assert_eq(cfg.specification, Some("Spec"))
  assert_eq(cfg.invariants, ["TypeOK", "TCConsistent", "Safety"])
  assert_eq(cfg.properties, ["EventuallyDone"])
  assert_eq(cfg.check_deadlock, false)
  assert_eq(cfg.constants.length(), 4)
}

///|
test "malformed inputs raise clean errors without panicking" {
  let bad_inputs = [
    "", "---- MODULE Broken", "---- MODULE M ----\nInit == (* unterminated\n====",
    "---- MODULE M ----\nInit == \"unterminated\n====", "---- MODULE M ----\nInit == [f EXCEPT ! = 1]\n====",
    "---- MODULE M ----\nInit == [a |-> ]\n====", "---- MODULE M ----\nInit == \\unknown 1\n====",
  ]
  for s in bad_inputs {
    let failed = try {
      let _ = @moon-tla.parse_module(s)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
