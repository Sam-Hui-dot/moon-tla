///|
/// Symmetry reduction groups extracted from `SYMMETRY SymName` (e.g. `Permutations(RM)`).
priv struct SymmetrySpec {
  groups : Array[Array[String]]
  total_perms : Int32
}

///|
fn empty_symmetry_spec() -> SymmetrySpec {
  { groups: [], total_perms: 1, }
}

///|
fn factorial_capped(n : Int32, cap : Int32) -> Int32 {
  let mut acc = 1
  for i = 2; i <= n; i = i + 1 {
    acc = acc * i
    if acc > cap {
      return cap + 1
    }
  }
  acc
}

///|
fn collect_symmetry_expr(
  ctx : EvalCtx,
  expr : Expr,
  groups : Array[Array[String]],
  depth : Int32,
) -> Unit raise TlaError {
  if depth > 16 {
    raise CfgError("SYMMETRY definition recursion limit exceeded")
  }
  match expr {
    Call("Permutations", args) if args.length() == 1 => {
      let elems = expect_set(
        eval_expr(ctx, args[0]),
        "SYMMETRY Permutations argument",
      )
      let names : Array[String] = []
      for el in elems {
        match el {
          ModelVal(m) => names.push(m)
          _ =>
            raise CfgError(
              "SYMMETRY Permutations requires a set of model values, got \{format_val(el)}",
            )
        }
      }
      if names.length() >= 2 {
        names.sort()
        groups.push(names)
      }
    }
    Bin(SetUnion, a, b) => {
      collect_symmetry_expr(ctx, a, groups, depth + 1)
      collect_symmetry_expr(ctx, b, groups, depth + 1)
    }
    Ident(name) =>
      match ctx.lookup_op(name) {
        Some(op) if op.params.is_empty() =>
          collect_symmetry_expr(ctx, op.body, groups, depth + 1)
        _ =>
          raise CfgError(
            "unsupported SYMMETRY expression '\{name}' (expected Permutations(S))",
          )
      }
    _ =>
      raise CfgError(
        "unsupported SYMMETRY expression (expected Permutations(S) or union of Permutations)",
      )
  }
}

///|
fn extract_symmetry_spec(
  ctx : EvalCtx,
  sym_name : String?,
) -> SymmetrySpec raise TlaError {
  match sym_name {
    None => empty_symmetry_spec()
    Some(name) => {
      let groups : Array[Array[String]] = []
      match ctx.lookup_op(name) {
        Some(op) if op.params.is_empty() =>
          collect_symmetry_expr(ctx, op.body, groups, 0)
        _ => raise CfgError("SYMMETRY operator '\{name}' not found in module")
      }
      let mut total_perms = 1
      for g in groups {
        let f = factorial_capped(g.length(), 120)
        total_perms = if total_perms > 120 || f > 120 {
          121
        } else {
          total_perms * f
        }
      }
      { groups, total_perms, }
    }
  }
}

///|
fn permute_val(v : TlaVal, mapping : Map[String, String]) -> TlaVal {
  match v {
    Bool(_) | Int(_) | Str(_) => v
    ModelVal(m) =>
      match mapping.get(m) {
        Some(rep) => ModelVal(rep)
        None => v
      }
    Set(xs) => {
      let out : Array[TlaVal] = []
      for x in xs {
        out.push(permute_val(x, mapping))
      }
      make_set(out)
    }
    Tuple(xs) => {
      let out : Array[TlaVal] = []
      for x in xs {
        out.push(permute_val(x, mapping))
      }
      Tuple(out)
    }
    Func(entries) => {
      let out : Array[(TlaVal, TlaVal)] = []
      for pair in entries {
        out.push((permute_val(pair.0, mapping), permute_val(pair.1, mapping)))
      }
      make_func(out)
    }
  }
}

///|
fn permute_state(
  vals : Array[TlaVal],
  mapping : Map[String, String],
) -> Array[TlaVal] {
  let out : Array[TlaVal] = []
  for v in vals {
    out.push(permute_val(v, mapping))
  }
  out
}

///|
fn compare_state_vals(a : Array[TlaVal], b : Array[TlaVal]) -> Int32 {
  let n = a.length()
  for i = 0; i < n; i = i + 1 {
    let c = compare_val(a[i], b[i])
    if c != 0 {
      return c
    }
  }
  0
}

///|
fn generate_group_perms(names : Array[String]) -> Array[Array[String]] {
  let out : Array[Array[String]] = []
  let used : Array[Bool] = Array::make(names.length(), false)
  let cur : Array[String] = []
  fn dfs() -> Unit {
    if cur.length() == names.length() {
      out.push(cur.copy())
      return
    }
    for i = 0; i < names.length(); i = i + 1 {
      if !used[i] {
        used[i] = true
        cur.push(names[i])
        dfs()
        let _ = cur.pop()
        used[i] = false
      }
    }
  }
  dfs()
  out
}

///|
fn scan_first_occurrence(
  v : TlaVal,
  member_group : Map[String, Int32],
  groups : Array[Array[String]],
  next_slot : Array[Int32],
  mapping : Map[String, String],
) -> Unit {
  match v {
    Bool(_) | Int(_) | Str(_) => ()
    ModelVal(m) =>
      if !mapping.contains(m) {
        match member_group.get(m) {
          Some(gi) => {
            let slot = next_slot[gi]
            next_slot[gi] = slot + 1
            mapping.set(m, groups[gi][slot])
          }
          None => ()
        }
      }
    Set(xs) | Tuple(xs) =>
      for x in xs {
        scan_first_occurrence(x, member_group, groups, next_slot, mapping)
      }
    Func(entries) =>
      for pair in entries {
        scan_first_occurrence(pair.0, member_group, groups, next_slot, mapping)
        scan_first_occurrence(pair.1, member_group, groups, next_slot, mapping)
      }
  }
}

///|
/// Compute a canonical representative state under the configured symmetry groups.
/// For groups with total size <= 120 (e.g. |S| <= 5), returns the exact
/// lexicographically minimum orbit representative (matching Java TLC SYMMETRY).
fn canonicalize_state(
  sym : SymmetrySpec,
  vals : Array[TlaVal],
) -> Array[TlaVal] {
  if sym.groups.is_empty() {
    return vals
  }
  if sym.total_perms <= 120 {
    let all_group_perms : Array[Array[Array[String]]] = []
    for g in sym.groups {
      all_group_perms.push(generate_group_perms(g))
    }
    let mut best : Array[TlaVal]? = None
    let mapping : Map[String, String] = Map([])
    fn search(gi : Int32) -> Unit {
      if gi == sym.groups.length() {
        let cand = permute_state(vals, mapping)
        match best {
          None => best = Some(cand)
          Some(cur_best) =>
            if compare_state_vals(cand, cur_best) < 0 {
              best = Some(cand)
            }
        }
        return
      }
      let orig = sym.groups[gi]
      for perm in all_group_perms[gi] {
        for i = 0; i < orig.length(); i = i + 1 {
          mapping.set(orig[i], perm[i])
        }
        search(gi + 1)
      }
    }
    search(0)
    match best {
      Some(b) => b
      None => vals
    }
  } else {
    let member_group : Map[String, Int32] = Map([])
    for gi = 0; gi < sym.groups.length(); gi = gi + 1 {
      for m in sym.groups[gi] {
        member_group.set(m, gi)
      }
    }
    let next_slot : Array[Int32] = Array::make(sym.groups.length(), 0)
    let mapping : Map[String, String] = Map([])
    for v in vals {
      scan_first_occurrence(v, member_group, sym.groups, next_slot, mapping)
    }
    permute_state(vals, mapping)
  }
}
