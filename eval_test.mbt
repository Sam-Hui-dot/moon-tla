///|
test "tla euclidean division mod and arithmetic" {
  let e1 = @moon-tla.parse_expr_str("(-1) \\div 3")
  assert_eq(@moon-tla.eval_expr_standalone(e1), Int(-1L))
  let e2 = @moon-tla.parse_expr_str("(-1) % 3")
  assert_eq(@moon-tla.eval_expr_standalone(e2), Int(2L))
  let e3 = @moon-tla.parse_expr_str("7 \\div 2")
  assert_eq(@moon-tla.eval_expr_standalone(e3), Int(3L))
  let e4 = @moon-tla.parse_expr_str("2 ^ 10")
  assert_eq(@moon-tla.eval_expr_standalone(e4), Int(1024L))
}

///|
test "canonical set equality and fingerprint stability" {
  let s1 = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("{3, 1, 2, 1}"),
  )
  let s2 = @moon-tla.eval_expr_standalone(@moon-tla.parse_expr_str("1..3"))
  assert_eq(s1, s2)
  assert_eq(@moon-tla.fingerprint_val(s1), @moon-tla.fingerprint_val(s2))

  let f1 = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("[i \\in 1..3 |-> i * 10]"),
  )
  let t1 = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("<<10, 20, 30>>"),
  )
  assert_eq(f1, t1)
  assert_eq(@moon-tla.fingerprint_val(f1), @moon-tla.fingerprint_val(t1))
}

///|
test "sequences records except and tlc operators" {
  let r1 = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str(
      "LET r == [a |-> [x |-> 1], b |-> 2] IN [r EXCEPT !.a.x = @ + 5, !.b = 9]",
    ),
  )
  assert_eq(@moon-tla.format_val(r1), "[a |-> [x |-> 6], b |-> 9]")

  let seq_v = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("SubSeq(Append(<<1, 2>>, 3) \\o <<4>>, 2, 4)"),
  )
  assert_eq(@moon-tla.format_val(seq_v), "<<2, 3, 4>>")

  let merged = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("(\"a\" :> 1) @@ (\"a\" :> 9 @@ \"b\" :> 2)"),
  )
  assert_eq(@moon-tla.format_val(merged), "[a |-> 1, b |-> 2]")

  let sym = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str(
      "[x \\in {\"p\", \"q\"} |-> 42] \\in [{\"p\", \"q\"} -> Nat]",
    ),
  )
  assert_eq(sym, Bool(true))

  let card = @moon-tla.eval_expr_standalone(
    @moon-tla.parse_expr_str("Cardinality(SUBSET {1, 2, 3})"),
  )
  assert_eq(card, Int(8L))
}
