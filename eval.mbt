///|
/// Runtime evaluation environment for TLA+ expressions and operators.
priv struct EvalCtx {
  defs : Map[String, OpDef]
  consts : Map[String, TlaVal]
  var_index : Map[String, Int32]
  curr : Array[TlaVal]?
  next : Array[TlaVal?]?
  locals : Map[String, TlaVal]
  local_ops : Map[String, OpDef]
  at_val : TlaVal?
  depth : Int32
}

///|
fn EvalCtx::with_locals(
  self : EvalCtx,
  extra : Array[(String, TlaVal)],
) -> EvalCtx {
  let next_locals = self.locals.copy()
  for pair in extra {
    next_locals.set(pair.0, pair.1)
  }
  {
    defs: self.defs,
    consts: self.consts,
    var_index: self.var_index,
    curr: self.curr,
    next: self.next,
    locals: next_locals,
    local_ops: self.local_ops,
    at_val: self.at_val,
    depth: self.depth + 1,
  }
}

///|
fn EvalCtx::with_local_ops(self : EvalCtx, ops : Array[OpDef]) -> EvalCtx {
  let next_ops = self.local_ops.copy()
  for op in ops {
    next_ops.set(op.name, op)
  }
  {
    defs: self.defs,
    consts: self.consts,
    var_index: self.var_index,
    curr: self.curr,
    next: self.next,
    locals: self.locals,
    local_ops: next_ops,
    at_val: self.at_val,
    depth: self.depth + 1,
  }
}

///|
fn EvalCtx::with_at(self : EvalCtx, val : TlaVal) -> EvalCtx {
  {
    defs: self.defs,
    consts: self.consts,
    var_index: self.var_index,
    curr: self.curr,
    next: self.next,
    locals: self.locals,
    local_ops: self.local_ops,
    at_val: Some(val),
    depth: self.depth,
  }
}

///|
fn EvalCtx::lookup_op(self : EvalCtx, name : String) -> OpDef? {
  match self.local_ops.get(name) {
    Some(d) => Some(d)
    None => self.defs.get(name)
  }
}

///|
fn expect_bool(v : TlaVal, where_label : String) -> Bool raise TlaError {
  match v {
    Bool(b) => b
    _ =>
      raise EvalError(
        "expected BOOLEAN in \{where_label}, got \{format_val(v)}",
      )
  }
}

///|
fn expect_int(v : TlaVal, where_label : String) -> Int64 raise TlaError {
  match v {
    Int(n) => n
    _ =>
      raise EvalError(
        "expected integer in \{where_label}, got \{format_val(v)}",
      )
  }
}

///|
fn expect_set(v : TlaVal, where_label : String) -> Array[TlaVal] raise TlaError {
  match v {
    Set(elems) => elems
    _ => raise EvalError("expected set in \{where_label}, got \{format_val(v)}")
  }
}

///|
fn expect_tuple(
  v : TlaVal,
  where_label : String,
) -> Array[TlaVal] raise TlaError {
  match v {
    Tuple(items) => items
    _ =>
      raise EvalError(
        "expected sequence/tuple in \{where_label}, got \{format_val(v)}",
      )
  }
}

///|
/// TLA+ floor/Euclidean integer division (`\div`) and modulo (`%`) matching Java TLC.
fn tla_floor_div_mod(a : Int64, b : Int64) -> (Int64, Int64) raise TlaError {
  if b == 0L {
    raise EvalError("division by zero")
  }
  let q0 = a / b
  let r0 = a % b
  if r0 != 0L && (r0 < 0L) != (b < 0L) {
    (q0 - 1L, r0 + b)
  } else {
    (q0, r0)
  }
}

///|
fn tla_pow(base : Int64, exp : Int64) -> Int64 raise TlaError {
  if exp < 0L {
    raise EvalError("negative exponent \{exp} in integer power")
  }
  let mut res = 1L
  let mut b = base
  let mut e = exp
  while e > 0L {
    if (e & 1L) == 1L {
      res = res * b
    }
    b = b * b
    e = e >> 1
  }
  res
}

///|
fn bind_pattern(
  pat : BoundPat,
  val : TlaVal,
  out : Array[(String, TlaVal)],
) -> Unit raise TlaError {
  match pat {
    Single(name) => out.push((name, val))
    TuplePat(names) => {
      let items = expect_tuple(val, "tuple pattern binding")
      if items.length() != names.length() {
        raise EvalError(
          "tuple pattern arity mismatch: expected \{names.length()}, got \{items.length()}",
        )
      }
      for i = 0; i < names.length(); i = i + 1 {
        out.push((names[i], items[i]))
      }
    }
  }
}

///|
/// Enumerate all binding combinations across a list of `BoundGroup`s.
fn expand_bound_groups(
  ctx : EvalCtx,
  groups : Array[BoundGroup],
) -> Array[(Array[(String, TlaVal)], Array[TlaVal])] raise TlaError {
  let flat_pats : Array[(BoundPat, Expr)] = []
  for g in groups {
    for p in g.pats {
      flat_pats.push((p, g.domain))
    }
  }
  let results : Array[(Array[(String, TlaVal)], Array[TlaVal])] = []
  fn dfs(
    idx : Int32,
    cur_ctx : EvalCtx,
    bindings : Array[(String, TlaVal)],
    raw_vals : Array[TlaVal],
  ) -> Unit raise TlaError {
    if idx == flat_pats.length() {
      results.push((bindings.copy(), raw_vals.copy()))
      return
    }
    let (pat, dom_expr) = flat_pats[idx]
    let dom_val = eval_expr(cur_ctx, dom_expr)
    let elems = expect_set(dom_val, "quantifier domain")
    for elem in elems {
      let added : Array[(String, TlaVal)] = []
      bind_pattern(pat, elem, added)
      let next_ctx = cur_ctx.with_locals(added)
      let next_bindings = bindings.copy()
      for pair in added {
        next_bindings.push(pair)
      }
      let next_raw = raw_vals.copy()
      next_raw.push(elem)
      dfs(idx + 1, next_ctx, next_bindings, next_raw)
    }
  }
  dfs(0, ctx, [], [])
  results
}

///|
/// Symbolic membership test `val \in set_expr` avoiding materialization of
/// infinite sets (`Nat`, `Int`, `STRING`, `Seq(S)`) or huge function/record/power sets.
fn eval_membership(
  ctx : EvalCtx,
  val : TlaVal,
  set_expr : Expr,
) -> Bool raise TlaError {
  match set_expr {
    BuiltinSet("BOOLEAN") =>
      match val {
        Bool(_) => true
        _ => false
      }
    BuiltinSet("Nat") =>
      match val {
        Int(n) => n >= 0L
        _ => false
      }
    BuiltinSet("Int") =>
      match val {
        Int(_) => true
        _ => false
      }
    BuiltinSet("STRING") =>
      match val {
        Str(_) => true
        _ => false
      }
    Bin(Range, lo_e, hi_e) => {
      let lo = expect_int(eval_expr(ctx, lo_e), "interval lower bound")
      let hi = expect_int(eval_expr(ctx, hi_e), "interval upper bound")
      match val {
        Int(n) => n >= lo && n <= hi
        _ => false
      }
    }
    Bin(SetUnion, a, b) =>
      eval_membership(ctx, val, a) || eval_membership(ctx, val, b)
    Bin(SetInter, a, b) =>
      eval_membership(ctx, val, a) && eval_membership(ctx, val, b)
    Bin(SetDiff, a, b) =>
      eval_membership(ctx, val, a) && !eval_membership(ctx, val, b)
    Bin(Cross, a, b) =>
      match val {
        Tuple(items) if items.length() == 2 =>
          eval_membership(ctx, items[0], a) && eval_membership(ctx, items[1], b)
        _ => false
      }
    Unary(Subset, inner) =>
      match val {
        Set(elems) => {
          for e in elems {
            if !eval_membership(ctx, e, inner) {
              return false
            }
          }
          true
        }
        _ => false
      }
    FuncSet(dom_e, cod_e) => {
      let dom_set = expect_set(eval_expr(ctx, dom_e), "function set domain")
      match val {
        Tuple(items) => {
          if dom_set.length() != items.length() {
            return false
          }
          for i = 0; i < items.length(); i = i + 1 {
            if compare_val(dom_set[i], Int((i + 1).to_int64())) != 0 {
              return false
            }
            if !eval_membership(ctx, items[i], cod_e) {
              return false
            }
          }
          true
        }
        Func(entries) => {
          if dom_set.length() != entries.length() {
            return false
          }
          for i = 0; i < entries.length(); i = i + 1 {
            if compare_val(dom_set[i], entries[i].0) != 0 {
              return false
            }
            if !eval_membership(ctx, entries[i].1, cod_e) {
              return false
            }
          }
          true
        }
        _ => false
      }
    }
    RecordSet(fields) => {
      let sorted_fields = fields.copy()
      sorted_fields.sort_by(fn(a, b) { a.0.compare(b.0) })
      match val {
        Func(entries) => {
          if entries.length() != sorted_fields.length() {
            return false
          }
          for i = 0; i < entries.length(); i = i + 1 {
            match entries[i].0 {
              Str(k) if k == sorted_fields[i].0 =>
                if !eval_membership(ctx, entries[i].1, sorted_fields[i].1) {
                  return false
                }
              _ => return false
            }
          }
          true
        }
        Tuple(items) if items.is_empty() && sorted_fields.is_empty() => true
        _ => false
      }
    }
    Call("Seq", args) if args.length() == 1 =>
      match val {
        Tuple(items) => {
          for item in items {
            if !eval_membership(ctx, item, args[0]) {
              return false
            }
          }
          true
        }
        _ => false
      }
    _ => {
      let s = expect_set(eval_expr(ctx, set_expr), "\\in right-hand side")
      set_contains(s, val)
    }
  }
}

///|
fn eval_except_path(
  ctx : EvalCtx,
  cur : TlaVal,
  path : Array[ExceptStep],
  step_idx : Int32,
  rhs : Expr,
) -> TlaVal raise TlaError {
  if step_idx >= path.length() {
    return eval_expr(ctx.with_at(cur), rhs)
  }
  let key : TlaVal = match path[step_idx] {
    Field(fname) => Str(fname)
    Index(exprs) =>
      if exprs.length() == 1 {
        eval_expr(ctx, exprs[0])
      } else {
        let vals : Array[TlaVal] = []
        for e in exprs {
          vals.push(eval_expr(ctx, e))
        }
        Tuple(vals)
      }
  }
  match cur {
    Tuple(items) =>
      match key {
        Int(idx) => {
          let i = idx.to_int() - 1
          if i < 0 || i >= items.length() {
            raise EvalError(
              "EXCEPT index \{idx} out of bounds for tuple of length \{items.length()}",
            )
          }
          let updated = eval_except_path(ctx, items[i], path, step_idx + 1, rhs)
          let copy = items.copy()
          copy[i] = updated
          Tuple(copy)
        }
        _ =>
          raise EvalError("EXCEPT key \{format_val(key)} not in tuple domain")
      }
    Func(entries) => {
      let copy = entries.copy()
      let mut found = -1
      for i = 0; i < copy.length(); i = i + 1 {
        if compare_val(copy[i].0, key) == 0 {
          found = i
          break
        }
      }
      if found < 0 {
        raise EvalError("EXCEPT key \{format_val(key)} not in function domain")
      }
      let updated = eval_except_path(
        ctx,
        copy[found].1,
        path,
        step_idx + 1,
        rhs,
      )
      copy[found] = (copy[found].0, updated)
      make_func(copy)
    }
    _ =>
      raise EvalError(
        "EXCEPT target must be a function, record, or tuple, got \{format_val(cur)}",
      )
  }
}

///|
fn eval_builtin_call(
  ctx : EvalCtx,
  name : String,
  args : Array[Expr],
) -> TlaVal? raise TlaError {
  match name {
    "Len" if args.length() == 1 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "Len")
      Some(Int(items.length().to_int64()))
    }
    "Head" if args.length() == 1 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "Head")
      if items.is_empty() {
        raise EvalError("Head applied to empty sequence")
      }
      Some(items[0])
    }
    "Tail" if args.length() == 1 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "Tail")
      if items.is_empty() {
        raise EvalError("Tail applied to empty sequence")
      }
      let out : Array[TlaVal] = []
      for i = 1; i < items.length(); i = i + 1 {
        out.push(items[i])
      }
      Some(Tuple(out))
    }
    "Append" if args.length() == 2 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "Append")
      let elem = eval_expr(ctx, args[1])
      let out = items.copy()
      out.push(elem)
      Some(Tuple(out))
    }
    "SubSeq" if args.length() == 3 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "SubSeq")
      let m = expect_int(eval_expr(ctx, args[1]), "SubSeq start").to_int()
      let n = expect_int(eval_expr(ctx, args[2]), "SubSeq end").to_int()
      if m > n {
        return Some(Tuple([]))
      }
      if m < 1 || n > items.length() {
        raise EvalError(
          "SubSeq bounds \{m}..\{n} out of range 1..\{items.length()}",
        )
      }
      let out : Array[TlaVal] = []
      for i = m - 1; i < n; i = i + 1 {
        out.push(items[i])
      }
      Some(Tuple(out))
    }
    "SelectSeq" if args.length() == 2 => {
      let items = expect_tuple(eval_expr(ctx, args[0]), "SelectSeq")
      let pred_name = match args[1] {
        Ident(n) => n
        _ =>
          raise EvalError("SelectSeq expects an operator name as 2nd argument")
      }
      let op = match ctx.lookup_op(pred_name) {
        Some(d) if d.params.length() == 1 => d
        _ =>
          raise EvalError(
            "SelectSeq operator '\{pred_name}' not found with arity 1",
          )
      }
      let out : Array[TlaVal] = []
      for item in items {
        let sub = ctx.with_locals([(op.params[0], item)])
        if expect_bool(eval_expr(sub, op.body), "SelectSeq predicate") {
          out.push(item)
        }
      }
      Some(Tuple(out))
    }
    "Cardinality" if args.length() == 1 => {
      let elems = expect_set(eval_expr(ctx, args[0]), "Cardinality")
      Some(Int(elems.length().to_int64()))
    }
    "IsFiniteSet" if args.length() == 1 => {
      let _ = expect_set(eval_expr(ctx, args[0]), "IsFiniteSet")
      Some(Bool(true))
    }
    "PrintT" if args.length() == 1 => {
      let _ = eval_expr(ctx, args[0])
      Some(Bool(true))
    }
    "Print" if args.length() == 2 => {
      let _ = eval_expr(ctx, args[0])
      Some(eval_expr(ctx, args[1]))
    }
    "Assert" if args.length() == 2 => {
      let cond = expect_bool(eval_expr(ctx, args[0]), "Assert")
      let msg = format_val(eval_expr(ctx, args[1]))
      if !cond {
        raise EvalError("TLC Assert failed: \{msg}")
      }
      Some(Bool(true))
    }
    "ToString" if args.length() == 1 =>
      Some(Str(format_val(eval_expr(ctx, args[0]))))
    "Permutations" if args.length() == 1 => {
      let elems = expect_set(eval_expr(ctx, args[0]), "Permutations")
      if elems.length() > 5 {
        raise EvalError(
          "Permutations of set with \{elems.length()} elements exceeds direct enumeration limit (5); use inside SYMMETRY",
        )
      }
      let perms : Array[Array[TlaVal]] = []
      let used : Array[Bool] = Array::make(elems.length(), false)
      let cur : Array[TlaVal] = []
      fn gen() -> Unit {
        if cur.length() == elems.length() {
          perms.push(cur.copy())
          return
        }
        for i = 0; i < elems.length(); i = i + 1 {
          if !used[i] {
            used[i] = true
            cur.push(elems[i])
            gen()
            let _ = cur.pop()
            used[i] = false
          }
        }
      }
      gen()
      let funcs : Array[TlaVal] = []
      for p in perms {
        let entries : Array[(TlaVal, TlaVal)] = []
        for i = 0; i < elems.length(); i = i + 1 {
          entries.push((elems[i], p[i]))
        }
        funcs.push(make_func(entries))
      }
      Some(make_set(funcs))
    }
    _ => None
  }
}

///|
fn eval_expr(ctx : EvalCtx, expr : Expr) -> TlaVal raise TlaError {
  if ctx.depth > 256 {
    raise EvalError("maximum evaluation recursion depth (256) exceeded")
  }
  match expr {
    BoolLit(b) => Bool(b)
    IntLit(n) => Int(n)
    StrLit(s) => Str(s)
    At =>
      match ctx.at_val {
        Some(v) => v
        None => raise EvalError("'@' used outside EXCEPT clause")
      }
    BuiltinSet(name) =>
      match name {
        "BOOLEAN" => make_set([Bool(false), Bool(true)])
        _ =>
          raise EvalError(
            "cannot enumerate infinite built-in set '\{name}' (use inside \\in)",
          )
      }
    Ident(name) => {
      match ctx.locals.get(name) {
        Some(v) => return v
        None => ()
      }
      match ctx.consts.get(name) {
        Some(v) => return v
        None => ()
      }
      match ctx.var_index.get(name) {
        Some(idx) =>
          match ctx.curr {
            Some(st) => return st[idx]
            None =>
              match ctx.next {
                Some(ns) =>
                  match ns[idx] {
                    Some(v) => return v
                    None => raise EvalError("UNASSIGNED_VAR:\{name}")
                  }
                None => raise EvalError("UNASSIGNED_VAR:\{name}")
              }
          }
        None => ()
      }
      match ctx.lookup_op(name) {
        Some(op) if op.params.is_empty() => eval_expr(ctx, op.body)
        Some(_) => raise EvalError("operator '\{name}' requires arguments")
        None => raise EvalError("undefined identifier '\{name}'")
      }
    }
    Call(name, args) =>
      match ctx.lookup_op(name) {
        Some(op) => {
          if op.params.length() != args.length() {
            raise EvalError(
              "operator '\{name}' expects \{op.params.length()} args, got \{args.length()}",
            )
          }
          let pairs : Array[(String, TlaVal)] = []
          for i = 0; i < args.length(); i = i + 1 {
            pairs.push((op.params[i], eval_expr(ctx, args[i])))
          }
          let sub = ctx.with_locals(pairs)
          eval_expr(sub, op.body)
        }
        None =>
          match eval_builtin_call(ctx, name, args) {
            Some(v) => v
            None => raise EvalError("undefined operator '\{name}'")
          }
      }
    Unary(Prime, inner) =>
      match inner {
        Ident(name) =>
          match ctx.var_index.get(name) {
            Some(idx) =>
              match ctx.next {
                Some(ns) =>
                  match ns[idx] {
                    Some(v) => v
                    None => raise EvalError("UNASSIGNED_PRIMED:\{name}")
                  }
                None =>
                  raise EvalError(
                    "primed variable '\{name}'' evaluated outside action context",
                  )
              }
            None =>
              raise EvalError("cannot prime non-variable identifier '\{name}'")
          }
        _ =>
          // Prime distributes over state expressions by shifting curr -> next
          match ctx.next {
            Some(ns) => {
              let primed_curr : Array[TlaVal] = []
              for i = 0; i < ns.length(); i = i + 1 {
                match ns[i] {
                  Some(v) => primed_curr.push(v)
                  None => raise EvalError("UNASSIGNED_PRIMED:__expr__")
                }
              }
              let shifted : EvalCtx = {
                defs: ctx.defs,
                consts: ctx.consts,
                var_index: ctx.var_index,
                curr: Some(primed_curr),
                next: None,
                locals: ctx.locals,
                local_ops: ctx.local_ops,
                at_val: ctx.at_val,
                depth: ctx.depth + 1,
              }
              eval_expr(shifted, inner)
            }
            None => raise EvalError("prime operator evaluated outside action")
          }
      }
    Unary(Not, e) => Bool(!expect_bool(eval_expr(ctx, e), "~"))
    Unary(Neg, e) => Int(-expect_int(eval_expr(ctx, e), "unary -"))
    Unary(Domain, e) => func_domain(eval_expr(ctx, e))
    Unary(Union, e) => {
      let outer = expect_set(eval_expr(ctx, e), "UNION")
      let all : Array[TlaVal] = []
      for sub in outer {
        let inner = expect_set(sub, "UNION element")
        for x in inner {
          all.push(x)
        }
      }
      make_set(all)
    }
    Unary(Subset, e) => {
      let base = expect_set(eval_expr(ctx, e), "SUBSET")
      if base.length() > 16 {
        raise EvalError(
          "SUBSET of set with \{base.length()} elements exceeds enumeration limit (16)",
        )
      }
      let out : Array[TlaVal] = [Set([])]
      for elem in base {
        let cur_len = out.length()
        for i = 0; i < cur_len; i = i + 1 {
          match out[i] {
            Set(existing) => {
              let next_arr = existing.copy()
              next_arr.push(elem)
              out.push(Set(next_arr))
            }
            _ => ()
          }
        }
      }
      make_set(out)
    }
    Unary(Unchanged, _) =>
      raise EvalError("UNCHANGED evaluated outside action context")
    Unary(Enabled, act) =>
      match ctx.curr {
        Some(st) => {
          let succs = eval_action_states(ctx, st, act)
          Bool(!succs.is_empty())
        }
        None => raise EvalError("ENABLED requires a current state")
      }
    Unary(Always, e) | Unary(Eventually, e) => eval_expr(ctx, e)
    ConjList(items) => {
      for item in items {
        if !expect_bool(eval_expr(ctx, item), "/\\") {
          return Bool(false)
        }
      }
      Bool(true)
    }
    DisjList(items) => {
      for item in items {
        if expect_bool(eval_expr(ctx, item), "\\/") {
          return Bool(true)
        }
      }
      Bool(false)
    }
    Bin(And, a, b) =>
      if !expect_bool(eval_expr(ctx, a), "/\\") {
        Bool(false)
      } else {
        Bool(expect_bool(eval_expr(ctx, b), "/\\"))
      }
    Bin(Or, a, b) =>
      if expect_bool(eval_expr(ctx, a), "\\/") {
        Bool(true)
      } else {
        Bool(expect_bool(eval_expr(ctx, b), "\\/"))
      }
    Bin(Implies, a, b) =>
      if !expect_bool(eval_expr(ctx, a), "=>") {
        Bool(true)
      } else {
        Bool(expect_bool(eval_expr(ctx, b), "=>"))
      }
    Bin(Iff, a, b) => {
      let va = expect_bool(eval_expr(ctx, a), "<=>")
      let vb = expect_bool(eval_expr(ctx, b), "<=>")
      Bool(va == vb)
    }
    Bin(Eq, a, b) => Bool(eval_expr(ctx, a) == eval_expr(ctx, b))
    Bin(Neq, a, b) => Bool(eval_expr(ctx, a) != eval_expr(ctx, b))
    Bin(Lt, a, b) =>
      Bool(
        expect_int(eval_expr(ctx, a), "<") < expect_int(eval_expr(ctx, b), "<"),
      )
    Bin(Le, a, b) =>
      Bool(
        expect_int(eval_expr(ctx, a), "<=") <=
        expect_int(eval_expr(ctx, b), "<="),
      )
    Bin(Gt, a, b) =>
      Bool(
        expect_int(eval_expr(ctx, a), ">") > expect_int(eval_expr(ctx, b), ">"),
      )
    Bin(Ge, a, b) =>
      Bool(
        expect_int(eval_expr(ctx, a), ">=") >=
        expect_int(eval_expr(ctx, b), ">="),
      )
    Bin(In, a, b) => Bool(eval_membership(ctx, eval_expr(ctx, a), b))
    Bin(NotIn, a, b) => Bool(!eval_membership(ctx, eval_expr(ctx, a), b))
    Bin(SubsetEq, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\subseteq")
      let sb = expect_set(eval_expr(ctx, b), "\\subseteq")
      for x in sa {
        if !set_contains(sb, x) {
          return Bool(false)
        }
      }
      Bool(true)
    }
    Bin(ProperSubset, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\subset")
      let sb = expect_set(eval_expr(ctx, b), "\\subset")
      if sa.length() >= sb.length() {
        return Bool(false)
      }
      for x in sa {
        if !set_contains(sb, x) {
          return Bool(false)
        }
      }
      Bool(true)
    }
    Bin(SetUnion, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\cup")
      let sb = expect_set(eval_expr(ctx, b), "\\cup")
      let combined = sa.copy()
      for x in sb {
        combined.push(x)
      }
      make_set(combined)
    }
    Bin(SetInter, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\cap")
      let sb = expect_set(eval_expr(ctx, b), "\\cap")
      let out : Array[TlaVal] = []
      for x in sa {
        if set_contains(sb, x) {
          out.push(x)
        }
      }
      Set(out)
    }
    Bin(SetDiff, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\")
      let sb = expect_set(eval_expr(ctx, b), "\\")
      let out : Array[TlaVal] = []
      for x in sa {
        if !set_contains(sb, x) {
          out.push(x)
        }
      }
      Set(out)
    }
    Bin(Range, a, b) => {
      let lo = expect_int(eval_expr(ctx, a), "..")
      let hi = expect_int(eval_expr(ctx, b), "..")
      if hi < lo {
        return Set([])
      }
      if hi - lo > 100000L {
        raise EvalError(
          "interval \{lo}..\{hi} exceeds enumeration limit (100000)",
        )
      }
      let out : Array[TlaVal] = []
      let mut cur = lo
      while cur <= hi {
        out.push(Int(cur))
        cur += 1L
      }
      Set(out)
    }
    Bin(Concat, a, b) => {
      let sa = expect_tuple(eval_expr(ctx, a), "\\o")
      let sb = expect_tuple(eval_expr(ctx, b), "\\o")
      let out = sa.copy()
      for x in sb {
        out.push(x)
      }
      Tuple(out)
    }
    Bin(Add, a, b) =>
      Int(
        expect_int(eval_expr(ctx, a), "+") + expect_int(eval_expr(ctx, b), "+"),
      )
    Bin(Sub, a, b) =>
      Int(
        expect_int(eval_expr(ctx, a), "-") - expect_int(eval_expr(ctx, b), "-"),
      )
    Bin(Mul, a, b) =>
      Int(
        expect_int(eval_expr(ctx, a), "*") * expect_int(eval_expr(ctx, b), "*"),
      )
    Bin(IntDiv, a, b) => {
      let va = expect_int(eval_expr(ctx, a), "\\div")
      let vb = expect_int(eval_expr(ctx, b), "\\div")
      let (q, _) = tla_floor_div_mod(va, vb)
      Int(q)
    }
    Bin(Mod, a, b) => {
      let va = expect_int(eval_expr(ctx, a), "%")
      let vb = expect_int(eval_expr(ctx, b), "%")
      if vb <= 0L {
        raise EvalError("modulo divisor must be positive, got \{vb}")
      }
      let (_, r) = tla_floor_div_mod(va, vb)
      Int(r)
    }
    Bin(Pow, a, b) =>
      Int(
        tla_pow(
          expect_int(eval_expr(ctx, a), "^"),
          expect_int(eval_expr(ctx, b), "^"),
        ),
      )
    Bin(Cross, a, b) => {
      let sa = expect_set(eval_expr(ctx, a), "\\X")
      let sb = expect_set(eval_expr(ctx, b), "\\X")
      let out : Array[TlaVal] = []
      for x in sa {
        for y in sb {
          out.push(Tuple([x, y]))
        }
      }
      make_set(out)
    }
    Bin(MapTo, k, v) => make_func([(eval_expr(ctx, k), eval_expr(ctx, v))])
    Bin(MergeFunc, a, b) => {
      let va = eval_expr(ctx, a)
      let vb = eval_expr(ctx, b)
      let entries_a = val_to_func_entries(va, "@@")
      let entries_b = val_to_func_entries(vb, "@@")
      let merged : Array[(TlaVal, TlaVal)] = []
      for pa in entries_a {
        merged.push(pa)
      }
      for pb in entries_b {
        let mut exists = false
        for pa in entries_a {
          if compare_val(pa.0, pb.0) == 0 {
            exists = true
            break
          }
        }
        if !exists {
          merged.push(pb)
        }
      }
      make_func(merged)
    }
    Bin(LeadsTo, _, _) =>
      raise EvalError("temporal '~>' cannot be evaluated on a single state")
    IfThenElse(cond, t, f) =>
      if expect_bool(eval_expr(ctx, cond), "IF condition") {
        eval_expr(ctx, t)
      } else {
        eval_expr(ctx, f)
      }
    CaseExpr(arms, other) => {
      for arm in arms {
        if expect_bool(eval_expr(ctx, arm.0), "CASE guard") {
          return eval_expr(ctx, arm.1)
        }
      }
      match other {
        Some(e) => eval_expr(ctx, e)
        None => raise EvalError("no CASE arm matched and no OTHER branch given")
      }
    }
    LetIn(local_defs, body) => {
      let sub = ctx.with_local_ops(local_defs)
      eval_expr(sub, body)
    }
    ForAll(groups, body) => {
      let combos = expand_bound_groups(ctx, groups)
      for combo in combos {
        let sub = ctx.with_locals(combo.0)
        if !expect_bool(eval_expr(sub, body), "\\A body") {
          return Bool(false)
        }
      }
      Bool(true)
    }
    Exists(groups, body) => {
      let combos = expand_bound_groups(ctx, groups)
      for combo in combos {
        let sub = ctx.with_locals(combo.0)
        if expect_bool(eval_expr(sub, body), "\\E body") {
          return Bool(true)
        }
      }
      Bool(false)
    }
    Choose(pat, domain, pred) => {
      let elems = expect_set(eval_expr(ctx, domain), "CHOOSE domain")
      for elem in elems {
        let added : Array[(String, TlaVal)] = []
        bind_pattern(pat, elem, added)
        let sub = ctx.with_locals(added)
        if expect_bool(eval_expr(sub, pred), "CHOOSE predicate") {
          return elem
        }
      }
      raise EvalError("CHOOSE found no element satisfying predicate")
    }
    SetEnum(items) => {
      let vals : Array[TlaVal] = []
      for item in items {
        vals.push(eval_expr(ctx, item))
      }
      make_set(vals)
    }
    SetFilter(pat, domain, pred) => {
      let elems = expect_set(eval_expr(ctx, domain), "set filter domain")
      let kept : Array[TlaVal] = []
      for elem in elems {
        let added : Array[(String, TlaVal)] = []
        bind_pattern(pat, elem, added)
        let sub = ctx.with_locals(added)
        if expect_bool(eval_expr(sub, pred), "set filter predicate") {
          kept.push(elem)
        }
      }
      Set(kept)
    }
    SetMap(body, groups) => {
      let combos = expand_bound_groups(ctx, groups)
      let out : Array[TlaVal] = []
      for combo in combos {
        let sub = ctx.with_locals(combo.0)
        out.push(eval_expr(sub, body))
      }
      make_set(out)
    }
    TupleLit(items) => {
      let vals : Array[TlaVal] = []
      for item in items {
        vals.push(eval_expr(ctx, item))
      }
      Tuple(vals)
    }
    RecordLit(fields) => {
      let entries : Array[(TlaVal, TlaVal)] = []
      for f in fields {
        entries.push((Str(f.0), eval_expr(ctx, f.1)))
      }
      make_func(entries)
    }
    RecordSet(fields) => {
      let eval_fields : Array[(String, Array[TlaVal])] = []
      for f in fields {
        eval_fields.push((f.0, expect_set(eval_expr(ctx, f.1), "record set")))
      }
      let out : Array[TlaVal] = []
      fn build(idx : Int32, acc : Array[(TlaVal, TlaVal)]) -> Unit {
        if idx == eval_fields.length() {
          out.push(make_func(acc))
          return
        }
        let (fname, vals) = eval_fields[idx]
        for v in vals {
          let next_acc = acc.copy()
          next_acc.push((Str(fname), v))
          build(idx + 1, next_acc)
        }
      }
      build(0, [])
      make_set(out)
    }
    FuncDef(groups, body) => {
      let combos = expand_bound_groups(ctx, groups)
      let entries : Array[(TlaVal, TlaVal)] = []
      for combo in combos {
        let sub = ctx.with_locals(combo.0)
        let key = if combo.1.length() == 1 {
          combo.1[0]
        } else {
          Tuple(combo.1)
        }
        entries.push((key, eval_expr(sub, body)))
      }
      make_func(entries)
    }
    FuncSet(dom_e, cod_e) => {
      let dom = expect_set(eval_expr(ctx, dom_e), "function set domain")
      let cod = expect_set(eval_expr(ctx, cod_e), "function set codomain")
      let mut total = 1
      for _ in dom {
        total = total * cod.length()
        if total > 50000 {
          raise EvalError("function set enumeration exceeds limit (50000)")
        }
      }
      let out : Array[TlaVal] = []
      fn build_fn(idx : Int32, acc : Array[(TlaVal, TlaVal)]) -> Unit {
        if idx == dom.length() {
          out.push(make_func(acc))
          return
        }
        for c in cod {
          let next_acc = acc.copy()
          next_acc.push((dom[idx], c))
          build_fn(idx + 1, next_acc)
        }
      }
      build_fn(0, [])
      make_set(out)
    }
    FuncApply(target, args) => {
      let f = eval_expr(ctx, target)
      let key = if args.length() == 1 {
        eval_expr(ctx, args[0])
      } else {
        let vals : Array[TlaVal] = []
        for a in args {
          vals.push(eval_expr(ctx, a))
        }
        Tuple(vals)
      }
      match func_lookup(f, key) {
        Some(v) => v
        None =>
          raise EvalError(
            "key \{format_val(key)} not in domain of \{format_val(f)}",
          )
      }
    }
    RecordField(target, fname) => {
      let f = eval_expr(ctx, target)
      match func_lookup(f, Str(fname)) {
        Some(v) => v
        None =>
          raise EvalError(
            "field '\{fname}' not present in record \{format_val(f)}",
          )
      }
    }
    Except(base_e, clauses) => {
      let mut cur = eval_expr(ctx, base_e)
      for clause in clauses {
        cur = eval_except_path(ctx, cur, clause.path, 0, clause.value)
      }
      cur
    }
    StutterAction(_, _) | Fairness(_, _, _) =>
      raise EvalError("temporal action wrapper cannot be evaluated as a value")
  }
}

///|
fn val_to_func_entries(
  v : TlaVal,
  label : String,
) -> Array[(TlaVal, TlaVal)] raise TlaError {
  match v {
    Func(entries) => entries
    Tuple(items) => {
      let out : Array[(TlaVal, TlaVal)] = []
      for i = 0; i < items.length(); i = i + 1 {
        out.push((Int((i + 1).to_int64()), items[i]))
      }
      out
    }
    _ => raise EvalError("expected function/tuple in \{label}")
  }
}

///|
/// Evaluate a standalone TLA+ expression with optional constant bindings.
pub fn eval_expr_standalone(
  expr : Expr,
  constants~ : Array[(String, TlaVal)] = [],
) -> TlaVal raise TlaError {
  let consts : Map[String, TlaVal] = Map([])
  for pair in constants {
    consts.set(pair.0, pair.1)
  }
  let ctx : EvalCtx = {
    defs: Map([]),
    consts,
    var_index: Map([]),
    curr: None,
    next: None,
    locals: Map([]),
    local_ops: Map([]),
    at_val: None,
    depth: 0,
  }
  eval_expr(ctx, expr)
}
