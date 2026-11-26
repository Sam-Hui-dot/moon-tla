///|
/// Final verdict returned by the TLA+ model checker.
#derive(Debug, Eq, ToJson)
pub(all) enum CheckStatus {
  Ok
  InvariantViolation(String)
  Deadlock
  LivenessViolation(String)
  StateLimitReached(Int32)
}

///|
pub extend CheckStatus with @debug.Debug::{to_repr}

///|
pub extend CheckStatus with Eq::{not_equal, equal}

///|
pub extend CheckStatus with @json.ToJson::{to_json}

///|
/// Formatted variable assignment at a single trace state.
#derive(Debug, Eq, ToJson)
pub(all) struct VarBinding {
  name : String
  value : String
}

///|
pub extend VarBinding with @debug.Debug::{to_repr}

///|
pub extend VarBinding with Eq::{not_equal, equal}

///|
pub extend VarBinding with @json.ToJson::{to_json}

///|
/// Variable value transition between two consecutive trace states.
#derive(Debug, Eq, ToJson)
pub(all) struct VarDiff {
  name : String
  before : String
  after : String
}

///|
pub extend VarDiff with @debug.Debug::{to_repr}

///|
pub extend VarDiff with Eq::{not_equal, equal}

///|
pub extend VarDiff with @json.ToJson::{to_json}

///|
/// One step in a shortest safety, deadlock, or lasso liveness counterexample trace.
#derive(Debug, Eq, ToJson)
pub(all) struct TraceStep {
  step : Int32
  action : String
  state_id : Int32
  bindings : Array[VarBinding]
  diffs : Array[VarDiff]
}

///|
pub extend TraceStep with @debug.Debug::{to_repr}

///|
pub extend TraceStep with Eq::{not_equal, equal}

///|
pub extend TraceStep with @json.ToJson::{to_json}

///|
/// Node in the visualized state-space graph snapshot.
#derive(Debug, Eq, ToJson)
pub(all) struct GraphNode {
  id : Int32
  depth : Int32
  label : String
  detail : String
  is_init : Bool
  is_violation : Bool
  is_on_trace : Bool
}

///|
pub extend GraphNode with @debug.Debug::{to_repr}

///|
pub extend GraphNode with Eq::{not_equal, equal}

///|
pub extend GraphNode with @json.ToJson::{to_json}

///|
/// Directed transition edge in the visualized state-space graph snapshot.
#derive(Debug, Eq, ToJson)
pub(all) struct GraphEdge {
  from : Int32
  to : Int32
  action : String
  is_on_trace : Bool
}

///|
pub extend GraphEdge with @debug.Debug::{to_repr}

///|
pub extend GraphEdge with Eq::{not_equal, equal}

///|
pub extend GraphEdge with @json.ToJson::{to_json}

///|
/// Full diagnostic output of a model-checking run.
#derive(Debug, Eq, ToJson)
pub(all) struct CheckResult {
  module_name : String
  status : CheckStatus
  status_text : String
  states_generated : Int32
  distinct_states : Int32
  diameter : Int32
  transitions : Int32
  variables : Array[String]
  invariants_checked : Array[String]
  properties_checked : Array[String]
  trace : Array[TraceStep]
  lasso_loop_start : Int32?
  graph_nodes : Array[GraphNode]
  graph_edges : Array[GraphEdge]
}

///|
pub extend CheckResult with @debug.Debug::{to_repr}

///|
pub extend CheckResult with Eq::{not_equal, equal}

///|
pub extend CheckResult with @json.ToJson::{to_json}

///|
/// Execution bounds and overrides for `check_module`.
#derive(Debug, Eq)
pub(all) struct CheckOptions {
  max_states : Int32
  max_graph_nodes : Int32
  check_deadlock : Bool?
}

///|
pub extend CheckOptions with @debug.Debug::{to_repr}

///|
pub extend CheckOptions with Eq::{not_equal, equal}

///|
/// Construct default model-checking options.
pub fn check_options(
  max_states~ : Int32 = 200000,
  max_graph_nodes~ : Int32 = 80,
  check_deadlock~ : Bool? = None,
) -> CheckOptions {
  { max_states, max_graph_nodes, check_deadlock, }
}

///|
priv struct PartialState {
  vals : Array[TlaVal?]
  deferred : Array[Expr]
  action : String
}

///|
fn PartialState::clone(self : PartialState) -> PartialState {
  {
    vals: self.vals.copy(),
    deferred: self.deferred.copy(),
    action: self.action,
  }
}

///|
fn is_unassigned_err(err : Error) -> Bool {
  match err {
    EvalError(msg) =>
      msg.has_prefix("UNASSIGNED_VAR:") || msg.has_prefix("UNASSIGNED_PRIMED:")
    _ => false
  }
}

///|
fn flatten_conj(expr : Expr, out : Array[Expr]) -> Unit {
  match expr {
    ConjList(items) =>
      for item in items {
        flatten_conj(item, out)
      }
    Bin(And, a, b) => {
      flatten_conj(a, out)
      flatten_conj(b, out)
    }
    other => out.push(other)
  }
}

///|
fn flatten_disj(expr : Expr, out : Array[Expr]) -> Unit {
  match expr {
    DisjList(items) =>
      for item in items {
        flatten_disj(item, out)
      }
    Bin(Or, a, b) => {
      flatten_disj(a, out)
      flatten_disj(b, out)
    }
    other => out.push(other)
  }
}

///|
fn collect_unchanged_vars(
  ctx : EvalCtx,
  target : Expr,
  out : Array[Int32],
) -> Unit raise TlaError {
  match target {
    Ident(name) =>
      match ctx.var_index.get(name) {
        Some(idx) => out.push(idx)
        None =>
          match ctx.lookup_op(name) {
            Some(op) if op.params.is_empty() =>
              collect_unchanged_vars(ctx, op.body, out)
            _ =>
              raise CheckError(
                "UNCHANGED target '\{name}' is neither a variable nor a variable-tuple operator",
              )
          }
      }
    TupleLit(items) =>
      for item in items {
        collect_unchanged_vars(ctx, item, out)
      }
    _ => raise CheckError("unsupported expression inside UNCHANGED")
  }
}

///|
fn match_target_var(ctx : EvalCtx, expr : Expr, is_init : Bool) -> Int32? {
  if is_init {
    match expr {
      Ident(name) => ctx.var_index.get(name)
      _ => None
    }
  } else {
    match expr {
      Unary(Prime, Ident(name)) => ctx.var_index.get(name)
      _ => None
    }
  }
}

///|
fn format_action_call(name : String, vals : Array[TlaVal]) -> String {
  if vals.is_empty() {
    return name
  }
  let sb = StringBuilder()
  sb.write_string(name)
  sb.write_char('(')
  for i = 0; i < vals.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(format_val(vals[i]))
  }
  sb.write_char(')')
  sb.to_string()
}

///|
fn solve_expr(
  ctx : EvalCtx,
  expr : Expr,
  partials : Array[PartialState],
  is_init : Bool,
  top_next_name : String,
) -> Array[PartialState] raise TlaError {
  if partials.is_empty() {
    return []
  }
  match expr {
    ConjList(_) | Bin(And, _, _) => {
      let conjuncts : Array[Expr] = []
      flatten_conj(expr, conjuncts)
      let mut cur = partials
      for c in conjuncts {
        cur = solve_expr(ctx, c, cur, is_init, top_next_name)
        if cur.is_empty() {
          return []
        }
      }
      cur
    }
    DisjList(_) | Bin(Or, _, _) => {
      let disjuncts : Array[Expr] = []
      flatten_disj(expr, disjuncts)
      let out : Array[PartialState] = []
      for d in disjuncts {
        let cloned : Array[PartialState] = []
        for ps in partials {
          cloned.push(ps.clone())
        }
        let res = solve_expr(ctx, d, cloned, is_init, top_next_name)
        for r in res {
          out.push(r)
        }
      }
      out
    }
    Exists(groups, body) => {
      let out : Array[PartialState] = []
      for ps in partials {
        let ectx : EvalCtx = {
          defs: ctx.defs,
          consts: ctx.consts,
          var_index: ctx.var_index,
          curr: ctx.curr,
          next: Some(ps.vals),
          locals: ctx.locals,
          local_ops: ctx.local_ops,
          at_val: ctx.at_val,
          depth: ctx.depth + 1,
        }
        let combos = expand_bound_groups(ectx, groups)
        for combo in combos {
          let sub_ctx = ctx.with_locals(combo.0)
          let branch = solve_expr(
            sub_ctx,
            body,
            [ps.clone()],
            is_init,
            top_next_name,
          )
          for r in branch {
            out.push(r)
          }
        }
      }
      out
    }
    ForAll(groups, body) => {
      let out : Array[PartialState] = []
      for ps in partials {
        let ectx : EvalCtx = {
          defs: ctx.defs,
          consts: ctx.consts,
          var_index: ctx.var_index,
          curr: ctx.curr,
          next: Some(ps.vals),
          locals: ctx.locals,
          local_ops: ctx.local_ops,
          at_val: ctx.at_val,
          depth: ctx.depth + 1,
        }
        let combos = expand_bound_groups(ectx, groups)
        let mut cur : Array[PartialState] = [ps.clone()]
        for combo in combos {
          let sub_ctx = ctx.with_locals(combo.0)
          cur = solve_expr(sub_ctx, body, cur, is_init, top_next_name)
          if cur.is_empty() {
            break
          }
        }
        for r in cur {
          out.push(r)
        }
      }
      out
    }
    LetIn(local_defs, body) => {
      let sub_ctx = ctx.with_local_ops(local_defs)
      solve_expr(sub_ctx, body, partials, is_init, top_next_name)
    }
    IfThenElse(cond, then_e, else_e) => {
      let out : Array[PartialState] = []
      for ps in partials {
        let ectx : EvalCtx = {
          defs: ctx.defs,
          consts: ctx.consts,
          var_index: ctx.var_index,
          curr: ctx.curr,
          next: Some(ps.vals),
          locals: ctx.locals,
          local_ops: ctx.local_ops,
          at_val: ctx.at_val,
          depth: ctx.depth + 1,
        }
        let cond_res : Bool? = Some(
          expect_bool(eval_expr(ectx, cond), "action IF condition"),
        ) catch {
          err if is_unassigned_err(err) => None
          err => raise err
        }
        match cond_res {
          Some(true) => {
            let res = solve_expr(ctx, then_e, [ps], is_init, top_next_name)
            for r in res {
              out.push(r)
            }
          }
          Some(false) => {
            let res = solve_expr(ctx, else_e, [ps], is_init, top_next_name)
            for r in res {
              out.push(r)
            }
          }
          None => {
            let next_ps = ps.clone()
            next_ps.deferred.push(expr)
            out.push(next_ps)
          }
        }
      }
      out
    }
    CaseExpr(arms, other) => {
      let out : Array[PartialState] = []
      for ps in partials {
        let ectx : EvalCtx = {
          defs: ctx.defs,
          consts: ctx.consts,
          var_index: ctx.var_index,
          curr: ctx.curr,
          next: Some(ps.vals),
          locals: ctx.locals,
          local_ops: ctx.local_ops,
          at_val: ctx.at_val,
          depth: ctx.depth + 1,
        }
        let mut matched_body : Expr? = None
        for arm in arms {
          if expect_bool(eval_expr(ectx, arm.0), "action CASE guard") {
            matched_body = Some(arm.1)
            break
          }
        }
        match matched_body {
          Some(b) => {
            let res = solve_expr(ctx, b, [ps], is_init, top_next_name)
            for r in res {
              out.push(r)
            }
          }
          None =>
            match other {
              Some(o) => {
                let res = solve_expr(ctx, o, [ps], is_init, top_next_name)
                for r in res {
                  out.push(r)
                }
              }
              None => raise EvalError("no CASE arm matched in action")
            }
        }
      }
      out
    }
    Unary(Unchanged, target) => {
      if is_init {
        raise CheckError("UNCHANGED cannot appear in Init predicate")
      }
      let curr = match ctx.curr {
        Some(c) => c
        None => raise CheckError("UNCHANGED requires a current state")
      }
      let idxs : Array[Int32] = []
      collect_unchanged_vars(ctx, target, idxs)
      let out : Array[PartialState] = []
      for ps in partials {
        let next_ps = ps.clone()
        let mut ok = true
        for idx in idxs {
          match next_ps.vals[idx] {
            None => next_ps.vals[idx] = Some(curr[idx])
            Some(existing) =>
              if existing != curr[idx] {
                ok = false
                break
              }
          }
        }
        if ok {
          out.push(next_ps)
        }
      }
      out
    }
    Ident(name) =>
      match ctx.lookup_op(name) {
        Some(op) if op.params.is_empty() &&
          !ctx.locals.contains(name) &&
          !ctx.consts.contains(name) &&
          !ctx.var_index.contains(name) => {
          let labeled : Array[PartialState] = []
          for ps in partials {
            let c = ps.clone()
            if !is_init && c.action.is_empty() && name != top_next_name {
              labeled.push({ vals: c.vals, deferred: c.deferred, action: name, })
            } else {
              labeled.push(c)
            }
          }
          solve_expr(ctx, op.body, labeled, is_init, top_next_name)
        }
        _ => solve_atomic_constraint(ctx, expr, partials, is_init)
      }
    Call(name, arg_exprs) =>
      match ctx.lookup_op(name) {
        Some(op) => {
          if op.params.length() != arg_exprs.length() {
            raise EvalError(
              "operator '\{name}' expects \{op.params.length()} args, got \{arg_exprs.length()}",
            )
          }
          let out : Array[PartialState] = []
          for ps in partials {
            let ectx : EvalCtx = {
              defs: ctx.defs,
              consts: ctx.consts,
              var_index: ctx.var_index,
              curr: ctx.curr,
              next: Some(ps.vals),
              locals: ctx.locals,
              local_ops: ctx.local_ops,
              at_val: ctx.at_val,
              depth: ctx.depth + 1,
            }
            let pairs : Array[(String, TlaVal)] = []
            let arg_vals : Array[TlaVal] = []
            for i = 0; i < arg_exprs.length(); i = i + 1 {
              let v = eval_expr(ectx, arg_exprs[i])
              pairs.push((op.params[i], v))
              arg_vals.push(v)
            }
            let sub_ctx = ctx.with_locals(pairs)
            let next_act = if !is_init &&
              ps.action.is_empty() &&
              name != top_next_name {
              format_action_call(name, arg_vals)
            } else {
              ps.action
            }
            let branch = solve_expr(
              sub_ctx,
              op.body,
              [
                {
                  vals: ps.vals.copy(),
                  deferred: ps.deferred.copy(),
                  action: next_act,
                },
              ],
              is_init,
              top_next_name,
            )
            for r in branch {
              out.push(r)
            }
          }
          out
        }
        None => solve_atomic_constraint(ctx, expr, partials, is_init)
      }
    _ => solve_atomic_constraint(ctx, expr, partials, is_init)
  }
}

///|
fn solve_atomic_constraint(
  ctx : EvalCtx,
  expr : Expr,
  partials : Array[PartialState],
  is_init : Bool,
) -> Array[PartialState] raise TlaError {
  let out : Array[PartialState] = []
  for ps in partials {
    let ectx : EvalCtx = {
      defs: ctx.defs,
      consts: ctx.consts,
      var_index: ctx.var_index,
      curr: ctx.curr,
      next: Some(ps.vals),
      locals: ctx.locals,
      local_ops: ctx.local_ops,
      at_val: ctx.at_val,
      depth: ctx.depth + 1,
    }
    // 1. Variable equality assignment: v = rhs (Init) or v' = rhs (Next)
    match expr {
      Bin(Eq, lhs, rhs) => {
        match match_target_var(ctx, lhs, is_init) {
          Some(idx) if ps.vals[idx] is None => {
            let val_opt : TlaVal? = Some(eval_expr(ectx, rhs)) catch {
              err if is_unassigned_err(err) => None
              err => raise err
            }
            match val_opt {
              Some(v) => {
                let next_ps = ps.clone()
                next_ps.vals[idx] = Some(v)
                out.push(next_ps)
              }
              None => {
                let next_ps = ps.clone()
                next_ps.deferred.push(expr)
                out.push(next_ps)
              }
            }
            continue
          }
          _ => ()
        }
        match match_target_var(ctx, rhs, is_init) {
          Some(idx) if ps.vals[idx] is None => {
            let val_opt : TlaVal? = Some(eval_expr(ectx, lhs)) catch {
              err if is_unassigned_err(err) => None
              err => raise err
            }
            match val_opt {
              Some(v) => {
                let next_ps = ps.clone()
                next_ps.vals[idx] = Some(v)
                out.push(next_ps)
              }
              None => {
                let next_ps = ps.clone()
                next_ps.deferred.push(expr)
                out.push(next_ps)
              }
            }
            continue
          }
          _ => ()
        }
      }
      // 2. Nondeterministic set membership assignment: v \in S or v' \in S
      Bin(In, lhs, dom_e) =>
        match match_target_var(ctx, lhs, is_init) {
          Some(idx) if ps.vals[idx] is None => {
            let dom_opt : TlaVal? = Some(eval_expr(ectx, dom_e)) catch {
              err if is_unassigned_err(err) => None
              err => raise err
            }
            match dom_opt {
              Some(dom_val) => {
                let elems = expect_set(
                  dom_val, "nondeterministic \\in assignment",
                )
                for elem in elems {
                  let next_ps = ps.clone()
                  next_ps.vals[idx] = Some(elem)
                  out.push(next_ps)
                }
              }
              None => {
                let next_ps = ps.clone()
                next_ps.deferred.push(expr)
                out.push(next_ps)
              }
            }
            continue
          }
          _ => ()
        }
      _ => ()
    }

    // 3. Regular boolean guard (or equality/membership check on already-assigned var)
    let guard_opt : Bool? = Some(
      expect_bool(eval_expr(ectx, expr), "action guard"),
    ) catch {
      err if is_unassigned_err(err) => None
      err => raise err
    }
    match guard_opt {
      Some(true) => out.push(ps)
      Some(false) => ()
      None => {
        let next_ps = ps.clone()
        next_ps.deferred.push(expr)
        out.push(next_ps)
      }
    }
  }
  out
}

///|
fn finalize_partials(
  ctx : EvalCtx,
  var_names : Array[String],
  partials : Array[PartialState],
  is_init : Bool,
  top_next_name : String,
) -> Array[(String, Array[TlaVal])] raise TlaError {
  let resolved : Array[PartialState] = []
  for ps in partials {
    let mut work : Array[PartialState] = [ps]
    let mut round = 0
    while round < 8 {
      let mut any_deferred = false
      let next_work : Array[PartialState] = []
      for w in work {
        if w.deferred.is_empty() {
          next_work.push(w)
        } else {
          any_deferred = true
          let todo = w.deferred.copy()
          let seed : PartialState = {
            vals: w.vals.copy(),
            deferred: [],
            action: w.action,
          }
          let mut cur = [seed]
          for d in todo {
            cur = solve_expr(ctx, d, cur, is_init, top_next_name)
            if cur.is_empty() {
              break
            }
          }
          for c in cur {
            next_work.push(c)
          }
        }
      }
      work = next_work
      if !any_deferred {
        break
      }
      round += 1
    }
    for w in work {
      resolved.push(w)
    }
  }

  let complete : Array[(String, Array[TlaVal])] = []
  let num_vars = var_names.length()
  let phase_name = if is_init { "Init" } else { "Next" }
  for ps in resolved {
    if !ps.deferred.is_empty() {
      raise CheckError(
        "unresolved deferred constraint in \{phase_name} (ensure every variable is assigned before referencing it)",
      )
    }
    let vals : Array[TlaVal] = []
    for i = 0; i < num_vars; i = i + 1 {
      match ps.vals[i] {
        Some(v) => vals.push(v)
        None =>
          raise CheckError(
            "variable '\{var_names[i]}' was not assigned in \{phase_name}",
          )
      }
    }
    let label = if is_init {
      "Initial predicate"
    } else if ps.action.is_empty() {
      "Action"
    } else {
      ps.action
    }
    complete.push((label, vals))
  }
  complete
}

///|
fn eval_init_states(
  ctx : EvalCtx,
  var_names : Array[String],
  init_expr : Expr,
) -> Array[Array[TlaVal]] raise TlaError {
  let empty_vals : Array[TlaVal?] = Array::make(var_names.length(), None)
  let init_ctx : EvalCtx = {
    defs: ctx.defs,
    consts: ctx.consts,
    var_index: ctx.var_index,
    curr: None,
    next: None,
    locals: ctx.locals,
    local_ops: ctx.local_ops,
    at_val: None,
    depth: 0,
  }
  let partials = solve_expr(
    init_ctx,
    init_expr,
    [{ vals: empty_vals, deferred: [], action: "", }],
    true,
    "",
  )
  let pairs = finalize_partials(init_ctx, var_names, partials, true, "")
  let out : Array[Array[TlaVal]] = []
  for p in pairs {
    out.push(p.1)
  }
  out
}

///|
fn eval_action_states(
  ctx : EvalCtx,
  curr : Array[TlaVal],
  action_expr : Expr,
) -> Array[(String, Array[TlaVal])] raise TlaError {
  let num_vars = curr.length()
  let var_names : Array[String] = Array::make(num_vars, "")
  ctx.var_index.each(fn(k, idx) {
    if idx >= 0 && idx < num_vars {
      var_names[idx] = k
    }
  })
  let empty_vals : Array[TlaVal?] = Array::make(num_vars, None)
  let act_ctx : EvalCtx = {
    defs: ctx.defs,
    consts: ctx.consts,
    var_index: ctx.var_index,
    curr: Some(curr),
    next: None,
    locals: ctx.locals,
    local_ops: ctx.local_ops,
    at_val: None,
    depth: 0,
  }
  let top_name = match action_expr {
    Ident(n) => n
    _ => ""
  }
  let partials = solve_expr(
    act_ctx,
    action_expr,
    [{ vals: empty_vals, deferred: [], action: "", }],
    false,
    top_name,
  )
  finalize_partials(act_ctx, var_names, partials, false, top_name)
}

///|
priv struct ExtractedSpec {
  init_expr : Expr
  next_expr : Expr
  has_wf_next : Bool
}

///|
fn extract_spec(
  tla_mod : TlaModule,
  cfg : TlaConfig,
) -> ExtractedSpec raise TlaError {
  match cfg.specification {
    Some(spec_name) => {
      let def = match tla_mod.find_def(spec_name) {
        Some(d) => d
        None => raise CheckError("SPECIFICATION '\{spec_name}' not found")
      }
      let parts : Array[Expr] = []
      flatten_conj(def.body, parts)
      let init_parts : Array[Expr] = []
      let mut next_opt : Expr? = None
      let mut has_wf = false
      for p in parts {
        match p {
          Unary(Always, StutterAction(act, _)) => next_opt = Some(act)
          Unary(Always, act) => next_opt = Some(act)
          Fairness(_, _, _) => has_wf = true
          other => init_parts.push(other)
        }
      }
      let init_expr = if init_parts.is_empty() {
        raise CheckError(
          "SPECIFICATION '\{spec_name}' is missing an Init predicate",
        )
      } else if init_parts.length() == 1 {
        init_parts[0]
      } else {
        ConjList(init_parts)
      }
      let next_expr = match next_opt {
        Some(n) => n
        None =>
          raise CheckError(
            "SPECIFICATION '\{spec_name}' is missing [][Next]_vars",
          )
      }
      { init_expr, next_expr, has_wf_next: has_wf, }
    }
    None => {
      let init_name = match cfg.init {
        Some(n) => n
        None =>
          if tla_mod.find_def("Init") is Some(_) {
            "Init"
          } else {
            raise CheckError("no INIT or SPECIFICATION configured")
          }
      }
      let next_name = match cfg.next {
        Some(n) => n
        None =>
          if tla_mod.find_def("Next") is Some(_) {
            "Next"
          } else {
            raise CheckError("no NEXT or SPECIFICATION configured")
          }
      }
      if tla_mod.find_def(init_name) is None {
        raise CheckError("INIT operator '\{init_name}' not found in module")
      }
      if tla_mod.find_def(next_name) is None {
        raise CheckError("NEXT operator '\{next_name}' not found in module")
      }
      {
        init_expr: Ident(init_name),
        next_expr: Ident(next_name),
        has_wf_next: false,
      }
    }
  }
}

///|
fn build_eval_ctx(
  tla_mod : TlaModule,
  cfg : TlaConfig,
) -> EvalCtx raise TlaError {
  let defs : Map[String, OpDef] = Map([])
  for d in tla_mod.defs {
    defs.set(d.name, d)
  }
  for ov in cfg.overrides {
    match defs.get(ov.1) {
      Some(target_def) => defs.set(ov.0, target_def)
      None => raise CfgError("override target '\{ov.1}' not found in module")
    }
  }
  let consts : Map[String, TlaVal] = Map([])
  for pair in cfg.constants {
    consts.set(pair.0, cfg_value_to_val(pair.1))
  }
  for c in tla_mod.constants {
    if !consts.contains(c) && !defs.contains(c) {
      raise CfgError("CONSTANT '\{c}' is not assigned in .cfg")
    }
  }
  let var_index : Map[String, Int32] = Map([])
  for i = 0; i < tla_mod.variables.length(); i = i + 1 {
    var_index.set(tla_mod.variables[i], i)
  }
  {
    defs,
    consts,
    var_index,
    curr: None,
    next: None,
    locals: Map([]),
    local_ops: Map([]),
    at_val: None,
    depth: 0,
  }
}

///|
fn eval_state_pred(
  ctx : EvalCtx,
  state : Array[TlaVal],
  expr : Expr,
  label : String,
) -> Bool raise TlaError {
  let sctx : EvalCtx = {
    defs: ctx.defs,
    consts: ctx.consts,
    var_index: ctx.var_index,
    curr: Some(state),
    next: None,
    locals: Map([]),
    local_ops: Map([]),
    at_val: None,
    depth: 0,
  }
  expect_bool(eval_expr(sctx, expr), label)
}

///|
fn check_invariants_on_state(
  ctx : EvalCtx,
  state : Array[TlaVal],
  invariants : Array[String],
) -> String? raise TlaError {
  for inv_name in invariants {
    let ok = eval_state_pred(
      ctx,
      state,
      Ident(inv_name),
      "invariant \{inv_name}",
    )
    if !ok {
      return Some(inv_name)
    }
  }
  None
}

///|
priv struct StoredState {
  vals : Array[TlaVal]
  depth : Int32
  parent : Int32
  action : String
  is_init : Bool
}

///|
fn build_trace_from_ids(
  var_names : Array[String],
  states : Array[StoredState],
  ids_and_actions : Array[(Int32, String)],
) -> Array[TraceStep] {
  let steps : Array[TraceStep] = []
  for idx = 0; idx < ids_and_actions.length(); idx = idx + 1 {
    let (sid, act) = ids_and_actions[idx]
    let vals = states[sid].vals
    let bindings : Array[VarBinding] = []
    let diffs : Array[VarDiff] = []
    for v = 0; v < var_names.length(); v = v + 1 {
      let cur_str = format_val(vals[v])
      bindings.push({ name: var_names[v], value: cur_str, })
      if idx > 0 {
        let prev_vals = states[ids_and_actions[idx - 1].0].vals
        if prev_vals[v] != vals[v] {
          diffs.push({
            name: var_names[v],
            before: format_val(prev_vals[v]),
            after: cur_str,
          })
        }
      }
    }
    steps.push({ step: idx + 1, action: act, state_id: sid, bindings, diffs, })
  }
  steps
}

///|
fn reconstruct_bfs_trace(
  var_names : Array[String],
  states : Array[StoredState],
  end_id : Int32,
) -> Array[TraceStep] {
  let rev : Array[(Int32, String)] = []
  let mut cur = end_id
  while cur >= 0 {
    rev.push((cur, states[cur].action))
    cur = states[cur].parent
  }
  let forward : Array[(Int32, String)] = []
  for i = rev.length() - 1; i >= 0; i = i - 1 {
    forward.push(rev[i])
  }
  build_trace_from_ids(var_names, states, forward)
}

///|
fn summarize_state_short(
  var_names : Array[String],
  vals : Array[TlaVal],
) -> String {
  let sb = StringBuilder()
  for i = 0; i < var_names.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(var_names[i])
    sb.write_char('=')
    sb.write_string(format_val(vals[i]))
    if sb.to_string().length() > 38 && i + 1 < var_names.length() {
      sb.write_string(", ...")
      break
    }
  }
  sb.to_string()
}

///|
fn summarize_state_full(
  var_names : Array[String],
  vals : Array[TlaVal],
) -> String {
  let sb = StringBuilder()
  for i = 0; i < var_names.length(); i = i + 1 {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(var_names[i])
    sb.write_string(" = ")
    sb.write_string(format_val(vals[i]))
  }
  sb.to_string()
}

///|
fn build_graph_snapshot(
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  trace : Array[TraceStep],
  violation_id : Int32?,
  max_nodes : Int32,
) -> (Array[GraphNode], Array[GraphEdge]) {
  let trace_set : Map[Int32, Bool] = Map([])
  let trace_edges : Map[(Int32, Int32), Bool] = Map([])
  for i = 0; i < trace.length(); i = i + 1 {
    trace_set.set(trace[i].state_id, true)
    if i + 1 < trace.length() {
      trace_edges.set((trace[i].state_id, trace[i + 1].state_id), true)
    }
  }
  let keep : Map[Int32, Bool] = Map([])
  let keep_order : Array[Int32] = []
  fn add_keep(id : Int32) -> Unit {
    if !keep.contains(id) {
      keep.set(id, true)
      keep_order.push(id)
    }
  }
  // Always keep every trace state first
  for step in trace {
    add_keep(step.state_id)
  }
  // Fill remaining slots in BFS order
  for i = 0; i < states.length(); i = i + 1 {
    if keep_order.length() >= max_nodes {
      break
    }
    add_keep(i)
  }
  keep_order.sort()

  let nodes : Array[GraphNode] = []
  for id in keep_order {
    let st = states[id]
    let is_viol = match violation_id {
      Some(vid) => vid == id
      None => false
    }
    nodes.push({
      id,
      depth: st.depth,
      label: summarize_state_short(var_names, st.vals),
      detail: summarize_state_full(var_names, st.vals),
      is_init: st.is_init,
      is_violation: is_viol,
      is_on_trace: trace_set.contains(id),
    })
  }

  let edges : Array[GraphEdge] = []
  let seen_edge : Map[(Int32, Int32), Bool] = Map([])
  for from in keep_order {
    if from < adj.length() {
      for pair in adj[from] {
        let to = pair.0
        let act = pair.1
        if keep.contains(to) && !seen_edge.contains((from, to)) {
          seen_edge.set((from, to), true)
          edges.push({
            from,
            to,
            action: act,
            is_on_trace: trace_edges.contains((from, to)),
          })
        }
      }
    }
  }
  (nodes, edges)
}

///|
fn status_summary_text(status : CheckStatus) -> String {
  match status {
    Ok => "No errors found (all invariants and properties satisfied)"
    InvariantViolation(inv) => "Invariant \{inv} is violated"
    Deadlock => "Deadlock reached (no enabled Next transition)"
    LivenessViolation(prop) => "Temporal property \{prop} is violated"
    StateLimitReached(lim) => "State limit reached (\{lim} distinct states)"
  }
}

///|
/// Run explicit-state BFS safety, deadlock, and Tarjan SCC liveness checking
/// on a parsed `TlaModule` and `TlaConfig`.
pub fn check_module(
  tla_mod : TlaModule,
  cfg : TlaConfig,
  options~ : CheckOptions = check_options(),
) -> CheckResult raise TlaError {
  if tla_mod.variables.is_empty() {
    raise CheckError("module '\{tla_mod.name}' declares no VARIABLES")
  }
  let ctx = build_eval_ctx(tla_mod, cfg)
  for assume_e in tla_mod.assumes {
    let ok = expect_bool(eval_expr(ctx, assume_e), "ASSUME")
    if !ok {
      raise CheckError("module ASSUME predicate evaluated to FALSE")
    }
  }
  for inv in cfg.invariants {
    if ctx.lookup_op(inv) is None {
      raise CheckError("INVARIANT '\{inv}' not found in module")
    }
  }
  for prop in cfg.properties {
    if ctx.lookup_op(prop) is None {
      raise CheckError("PROPERTY '\{prop}' not found in module")
    }
  }

  let spec = extract_spec(tla_mod, cfg)
  let check_deadlock = match options.check_deadlock {
    Some(b) => b
    None => cfg.check_deadlock
  }

  let raw_inits = eval_init_states(ctx, tla_mod.variables, spec.init_expr)
  if raw_inits.is_empty() {
    raise CheckError("Init predicate produced 0 initial states")
  }

  let states : Array[StoredState] = []
  let adj : Array[Array[(Int32, String)]] = []
  let fp_to_id : Map[(UInt64, UInt64), Int32] = Map([])
  let mut states_generated = 0
  let mut transitions = 0
  let mut max_depth = 0
  let mut status : CheckStatus = Ok
  let mut violation_id : Int32? = None

  // Seed initial states (depth 0)
  for init_vals in raw_inits {
    states_generated += 1
    let fp = fingerprint_state(tla_mod.variables, init_vals)
    if !fp_to_id.contains(fp) {
      let id = states.length()
      fp_to_id.set(fp, id)
      states.push({
        vals: init_vals,
        depth: 0,
        parent: -1,
        action: "Initial predicate",
        is_init: true,
      })
      adj.push([])
      match check_invariants_on_state(ctx, init_vals, cfg.invariants) {
        Some(inv) => {
          status = InvariantViolation(inv)
          violation_id = Some(id)
          break
        }
        None => ()
      }
    }
  }

  // Breadth-first state-space exploration
  let mut head = 0
  while status == Ok && head < states.length() {
    let cur_id = head
    head += 1
    let cur_state = states[cur_id]
    if cur_state.depth > max_depth {
      max_depth = cur_state.depth
    }
    let succs = eval_action_states(ctx, cur_state.vals, spec.next_expr)
    if succs.is_empty() && check_deadlock {
      status = Deadlock
      violation_id = Some(cur_id)
      break
    }
    for pair in succs {
      let act = pair.0
      let next_vals = pair.1
      states_generated += 1
      transitions += 1
      let fp = fingerprint_state(tla_mod.variables, next_vals)
      match fp_to_id.get(fp) {
        Some(existing_id) => adj[cur_id].push((existing_id, act))
        None => {
          if states.length() >= options.max_states {
            status = StateLimitReached(options.max_states)
            break
          }
          let nid = states.length()
          let ndepth = cur_state.depth + 1
          if ndepth > max_depth {
            max_depth = ndepth
          }
          fp_to_id.set(fp, nid)
          states.push({
            vals: next_vals,
            depth: ndepth,
            parent: cur_id,
            action: act,
            is_init: false,
          })
          adj.push([])
          adj[cur_id].push((nid, act))
          match check_invariants_on_state(ctx, next_vals, cfg.invariants) {
            Some(inv) => {
              status = InvariantViolation(inv)
              violation_id = Some(nid)
              break
            }
            None => ()
          }
        }
      }
    }
  }

  let mut trace : Array[TraceStep] = []
  let mut lasso_loop_start : Int32? = None

  match violation_id {
    Some(vid) => trace = reconstruct_bfs_trace(tla_mod.variables, states, vid)
    None =>
      if status == Ok && !cfg.properties.is_empty() {
        match
          check_liveness_properties(
            ctx,
            tla_mod.variables,
            states,
            adj,
            cfg.properties,
            spec.has_wf_next,
          ) {
          Some((prop_name, ltrace, loop_idx, viol_state)) => {
            status = LivenessViolation(prop_name)
            trace = ltrace
            lasso_loop_start = loop_idx
            violation_id = Some(viol_state)
          }
          None => ()
        }
      }
  }

  let (graph_nodes, graph_edges) = build_graph_snapshot(
    tla_mod.variables,
    states,
    adj,
    trace,
    violation_id,
    options.max_graph_nodes,
  )

  {
    module_name: tla_mod.name,
    status,
    status_text: status_summary_text(status),
    states_generated,
    distinct_states: states.length(),
    diameter: if states.is_empty() {
      0
    } else {
      max_depth + 1
    },
    transitions,
    variables: tla_mod.variables,
    invariants_checked: cfg.invariants,
    properties_checked: cfg.properties,
    trace,
    lasso_loop_start,
    graph_nodes,
    graph_edges,
  }
}

///|
/// Convenience entry point: parse both `.tla` and `.cfg` source strings and run model checking.
pub fn check_spec_sources(
  tla_src : String,
  cfg_src : String,
  options~ : CheckOptions = check_options(),
) -> CheckResult raise TlaError {
  let tla_mod = parse_module(tla_src)
  let cfg = parse_cfg(cfg_src)
  check_module(tla_mod, cfg, options~)
}
