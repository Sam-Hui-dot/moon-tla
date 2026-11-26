///|
/// Tarjan strongly connected components over a boolean-masked subgraph of states.
fn tarjan_scc_masked(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  allowed : Array[Bool],
) -> Array[Array[Int32]] {
  let index_of : Array[Int32] = Array::make(n, -1)
  let lowlink : Array[Int32] = Array::make(n, 0)
  let on_stack : Array[Bool] = Array::make(n, false)
  let stack : Array[Int32] = []
  let sccs : Array[Array[Int32]] = []
  let mut cur_index = 0

  fn strongconnect(v : Int32) -> Unit {
    index_of[v] = cur_index
    lowlink[v] = cur_index
    cur_index += 1
    stack.push(v)
    on_stack[v] = true
    for pair in adj[v] {
      let w = pair.0
      if !allowed[w] {
        continue
      }
      if index_of[w] == -1 {
        strongconnect(w)
        if lowlink[w] < lowlink[v] {
          lowlink[v] = lowlink[w]
        }
      } else if on_stack[w] {
        if index_of[w] < lowlink[v] {
          lowlink[v] = index_of[w]
        }
      }
    }
    if lowlink[v] == index_of[v] {
      let comp : Array[Int32] = []
      while true {
        let w = stack.unsafe_pop()
        on_stack[w] = false
        comp.push(w)
        if w == v {
          break
        }
      }
      sccs.push(comp)
    }
  }

  for v = 0; v < n; v = v + 1 {
    if allowed[v] && index_of[v] == -1 {
      strongconnect(v)
    }
  }
  sccs
}

///|
/// Precomputed enabledness and non-stuttering taken transitions for one `WF_v(A)` / `SF_v(A)` obligation.
priv struct PreparedFairness {
  kind : FairnessKind
  enabled : Array[Bool]
  taken_edges : Map[(Int32, Int32), Bool]
}

///|
fn eval_vars_val(
  ctx : EvalCtx,
  state : Array[TlaVal],
  vars_expr : Expr,
) -> TlaVal raise TlaError {
  let sctx : EvalCtx = {
    defs: ctx.defs,
    consts: ctx.consts,
    var_index: ctx.var_index,
    curr: Some(state),
    next: None,
    locals: ctx.locals,
    local_ops: ctx.local_ops,
    at_val: None,
    depth: 0,
  }
  eval_expr(sctx, vars_expr)
}

///|
fn prepare_fairness(
  ctx : EvalCtx,
  var_names : Array[String],
  states : Array[StoredState],
  fp_to_id : Map[(UInt64, UInt64), Int32],
  sym_spec : SymmetrySpec,
  symmetry_applied : Bool,
  fairness : Array[FairnessClause],
) -> Array[PreparedFairness] raise TlaError {
  let n = states.length()
  let prepared : Array[PreparedFairness] = []
  for fc in fairness {
    let fctx = if fc.bindings.is_empty() {
      ctx
    } else {
      ctx.with_locals(fc.bindings)
    }
    let enabled : Array[Bool] = Array::make(n, false)
    let taken_edges : Map[(Int32, Int32), Bool] = Map([])
    for u = 0; u < n; u = u + 1 {
      let succs = eval_action_states(fctx, states[u].vals, fc.action_expr)
      if succs.is_empty() {
        continue
      }
      let v_u = eval_vars_val(fctx, states[u].vals, fc.vars_expr)
      for pair in succs {
        let next_vals = pair.1
        let v_next = eval_vars_val(fctx, next_vals, fc.vars_expr)
        if compare_val(v_u, v_next) != 0 {
          enabled[u] = true
          let canon_next = if symmetry_applied {
            canonicalize_state(sym_spec, next_vals)
          } else {
            next_vals
          }
          let fp = fingerprint_state(var_names, canon_next)
          match fp_to_id.get(fp) {
            Some(w) => taken_edges.set((u, w), true)
            None => ()
          }
        }
      }
    }
    prepared.push({ kind: fc.kind, enabled, taken_edges, })
  }
  prepared
}

///|
fn has_taken_edge_in_comp(
  adj : Array[Array[(Int32, String)]],
  comp : Array[Int32],
  in_comp : Array[Bool],
  taken_edges : Map[(Int32, Int32), Bool],
) -> Bool {
  for u in comp {
    for pair in adj[u] {
      let w = pair.0
      if in_comp[w] && taken_edges.contains((u, w)) {
        return true
      }
    }
  }
  false
}

///|
/// Emerson-Lei iterative SCC fairness pruning.
/// Returns all maximal SCCs inside `allowed` that admit an infinite execution
/// satisfying every `WF_v(A)` and `SF_v(A)` obligation.
fn find_fair_sccs(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  allowed : Array[Bool],
  fairness : Array[PreparedFairness],
) -> Array[Array[Int32]] {
  let fair_sccs : Array[Array[Int32]] = []
  let worklist : Array[Array[Bool]] = [allowed.copy()]

  while !worklist.is_empty() {
    let mask = worklist.unsafe_pop()
    let sccs = tarjan_scc_masked(n, adj, mask)
    for comp in sccs {
      if comp.length() == 1 {
        let v = comp[0]
        // Singleton {v} can stutter forever iff NO WF or SF obligation is enabled at v
        let mut blocked_by_fairness = false
        for fc in fairness {
          if fc.enabled[v] {
            blocked_by_fairness = true
            break
          }
        }
        if !blocked_by_fairness {
          fair_sccs.push(comp)
        }
        continue
      }

      // Multi-state SCC (|C| >= 2)
      let in_comp : Array[Bool] = Array::make(n, false)
      for v in comp {
        in_comp[v] = true
      }

      let mut rejected = false
      let mut pruned = false
      let next_mask = in_comp.copy()

      for fc in fairness {
        if has_taken_edge_in_comp(adj, comp, in_comp, fc.taken_edges) {
          continue
        }
        match fc.kind {
          Weak => {
            // WF fails iff EVERY state in C has the action enabled
            let mut all_enabled = true
            for v in comp {
              if !fc.enabled[v] {
                all_enabled = false
                break
              }
            }
            if all_enabled {
              rejected = true
              break
            }
          }
          Strong => {
            // SF fails if ANY state in C has the action enabled without being taken;
            // prune all enabled states and re-run Tarjan on the remaining subgraph.
            let mut any_enabled = false
            for v in comp {
              if fc.enabled[v] {
                next_mask[v] = false
                any_enabled = true
              }
            }
            if any_enabled {
              pruned = true
            }
          }
        }
      }

      if rejected {
        continue
      }
      if pruned {
        let mut remaining = 0
        for v in comp {
          if next_mask[v] {
            remaining += 1
          }
        }
        if remaining > 0 {
          worklist.push(next_mask)
        }
      } else {
        fair_sccs.push(comp)
      }
    }
  }
  fair_sccs
}

///|
/// Find shortest path inside `allowed` subgraph from any state in `starts` to any state in `targets`.
fn bfs_path_masked(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  allowed : Array[Bool],
  starts : Array[Int32],
  is_target : Array[Bool],
) -> Array[(Int32, String)]? {
  let visited : Array[Bool] = Array::make(n, false)
  let parent : Array[Int32] = Array::make(n, -1)
  let parent_act : Array[String] = Array::make(n, "")
  let queue : Array[Int32] = []
  for s in starts {
    if allowed[s] && !visited[s] {
      visited[s] = true
      if is_target[s] {
        return Some([(s, "")])
      }
      queue.push(s)
    }
  }
  let mut head = 0
  let mut found = -1
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for pair in adj[u] {
      let w = pair.0
      let act = pair.1
      if allowed[w] && !visited[w] {
        visited[w] = true
        parent[w] = u
        parent_act[w] = act
        if is_target[w] {
          found = w
          break
        }
        queue.push(w)
      }
    }
    if found >= 0 {
      break
    }
  }
  if found < 0 {
    return None
  }
  let rev : Array[(Int32, String)] = []
  let mut cur = found
  while cur >= 0 {
    rev.push((cur, parent_act[cur]))
    cur = parent[cur]
  }
  let path : Array[(Int32, String)] = []
  for i = rev.length() - 1; i >= 0; i = i - 1 {
    path.push(rev[i])
  }
  Some(path)
}

///|
/// Find shortest path inside `in_scc` from `src` to `dst` (excluding `src` itself).
fn bfs_shortest_in_scc(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  in_scc : Array[Bool],
  src : Int32,
  dst : Int32,
) -> Array[(Int32, String)] {
  if src == dst {
    return []
  }
  let visited : Array[Bool] = Array::make(n, false)
  let parent : Array[Int32] = Array::make(n, -1)
  let parent_act : Array[String] = Array::make(n, "")
  let queue : Array[Int32] = [src]
  visited[src] = true
  let mut head = 0
  let mut found = false
  while head < queue.length() && !found {
    let u = queue[head]
    head += 1
    for pair in adj[u] {
      let w = pair.0
      if in_scc[w] && !visited[w] {
        visited[w] = true
        parent[w] = u
        parent_act[w] = pair.1
        if w == dst {
          found = true
          break
        }
        queue.push(w)
      }
    }
  }
  if !found {
    return []
  }
  let rev : Array[(Int32, String)] = []
  let mut cur = dst
  while cur != src && cur >= 0 {
    rev.push((cur, parent_act[cur]))
    cur = parent[cur]
  }
  let out : Array[(Int32, String)] = []
  for i = rev.length() - 1; i >= 0; i = i - 1 {
    out.push(rev[i])
  }
  out
}

///|
/// Find a fair cycle starting and ending at `anchor` inside `comp`.
/// Covers at least one taken edge for each fairness clause active in `comp`,
/// or falls back to the shortest non-empty cycle / stuttering self-loop.
fn find_fair_cycle_in_scc(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  comp : Array[Int32],
  in_scc : Array[Bool],
  anchor : Int32,
  fairness : Array[PreparedFairness],
) -> Array[(Int32, String)] {
  if comp.length() == 1 {
    for pair in adj[anchor] {
      if pair.0 == anchor {
        return [(anchor, pair.1)]
      }
    }
    return [(anchor, "Stutter")]
  }

  // Collect one representative edge per fairness obligation that needs to be visited
  let needed_edges : Array[(Int32, Int32, String)] = []
  for fc in fairness {
    let mut picked : (Int32, Int32, String)? = None
    for u in comp {
      for pair in adj[u] {
        let w = pair.0
        if in_scc[w] && fc.taken_edges.contains((u, w)) {
          picked = Some((u, w, pair.1))
          break
        }
      }
      if picked is Some(_) {
        break
      }
    }
    match picked {
      Some(e) => needed_edges.push(e)
      None => ()
    }
  }

  if !needed_edges.is_empty() {
    let cycle : Array[(Int32, String)] = []
    let mut cur = anchor
    for e in needed_edges {
      let (u, w, act) = e
      let leg = bfs_shortest_in_scc(n, adj, in_scc, cur, u)
      for step in leg {
        cycle.push(step)
      }
      cycle.push((w, act))
      cur = w
    }
    let back = bfs_shortest_in_scc(n, adj, in_scc, cur, anchor)
    for step in back {
      cycle.push(step)
    }
    if !cycle.is_empty() {
      return cycle
    }
  }

  // Shortest non-empty cycle from anchor back to anchor
  let visited : Array[Bool] = Array::make(n, false)
  let parent : Array[Int32] = Array::make(n, -1)
  let parent_act : Array[String] = Array::make(n, "")
  let queue : Array[Int32] = []
  for pair in adj[anchor] {
    let w = pair.0
    if in_scc[w] && !visited[w] {
      visited[w] = true
      parent[w] = anchor
      parent_act[w] = pair.1
      queue.push(w)
    }
  }
  let mut head = 0
  let mut back_from = -1
  let mut back_act = ""
  while head < queue.length() {
    let u = queue[head]
    head += 1
    for pair in adj[u] {
      let w = pair.0
      if w == anchor {
        back_from = u
        back_act = pair.1
        break
      }
      if in_scc[w] && !visited[w] {
        visited[w] = true
        parent[w] = u
        parent_act[w] = pair.1
        queue.push(w)
      }
    }
    if back_from >= 0 {
      break
    }
  }
  if back_from < 0 {
    return [(anchor, "Stutter")]
  }
  let rev : Array[(Int32, String)] = []
  let mut cur = back_from
  while cur != anchor && cur >= 0 {
    rev.push((cur, parent_act[cur]))
    cur = parent[cur]
  }
  let cycle : Array[(Int32, String)] = []
  for i = rev.length() - 1; i >= 0; i = i - 1 {
    cycle.push(rev[i])
  }
  cycle.push((anchor, back_act))
  cycle
}

///|
/// Check for a fair infinite execution avoiding `goal` starting from any state in `start_ids`.
fn find_avoidance_lasso(
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  start_ids : Array[Int32],
  goal_holds : Array[Bool],
  fairness : Array[PreparedFairness],
) -> (Array[TraceStep], Int32?, Int32)? {
  let n = states.length()
  let allowed : Array[Bool] = Array::make(n, false)
  for i = 0; i < n; i = i + 1 {
    allowed[i] = !goal_holds[i]
  }
  let fair_sccs = find_fair_sccs(n, adj, allowed, fairness)
  let bad_target : Array[Bool] = Array::make(n, false)
  let scc_of : Array[Int32] = Array::make(n, -1)
  for ci = 0; ci < fair_sccs.length(); ci = ci + 1 {
    for v in fair_sccs[ci] {
      bad_target[v] = true
      scc_of[v] = ci
    }
  }
  match bfs_path_masked(n, adj, allowed, start_ids, bad_target) {
    None => None
    Some(suffix) => {
      let start_id = suffix[0].0
      let anchor = suffix[suffix.length() - 1].0
      let rev_prefix : Array[(Int32, String)] = []
      let mut cur = start_id
      while cur >= 0 {
        rev_prefix.push((cur, states[cur].action))
        cur = states[cur].parent
      }
      let combined : Array[(Int32, String)] = []
      for i = rev_prefix.length() - 1; i >= 0; i = i - 1 {
        combined.push(rev_prefix[i])
      }
      for i = 1; i < suffix.length(); i = i + 1 {
        combined.push(suffix[i])
      }
      let loop_step = combined.length()
      let ci = scc_of[anchor]
      let comp = if ci >= 0 { fair_sccs[ci] } else { [anchor] }
      let in_scc : Array[Bool] = Array::make(n, false)
      for v in comp {
        in_scc[v] = true
      }
      let cycle = find_fair_cycle_in_scc(n, adj, comp, in_scc, anchor, fairness)
      for step in cycle {
        combined.push(step)
      }
      let trace = build_trace_from_ids(var_names, states, combined)
      Some((trace, Some(loop_step), anchor))
    }
  }
}

///|
fn eval_state_pred_ctx(
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
    locals: ctx.locals,
    local_ops: ctx.local_ops,
    at_val: None,
    depth: 0,
  }
  expect_bool(eval_expr(sctx, expr), label)
}

///|
fn check_temporal_expr(
  ctx : EvalCtx,
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  init_ids : Array[Int32],
  all_ids : Array[Int32],
  prop_name : String,
  expr : Expr,
  fairness : Array[PreparedFairness],
  depth : Int32,
) -> (String, Array[TraceStep], Int32?, Int32)? raise TlaError {
  if depth > 16 {
    raise CheckError("temporal property '\{prop_name}' nesting depth exceeded")
  }
  let n = states.length()
  match expr {
    ForAll(groups, body) => {
      let combos = expand_bound_groups(ctx, groups)
      for combo in combos {
        let sub = ctx.with_locals(combo.0)
        match
          check_temporal_expr(
            sub,
            var_names,
            states,
            adj,
            init_ids,
            all_ids,
            prop_name,
            body,
            fairness,
            depth + 1,
          ) {
          Some(res) => return Some(res)
          None => ()
        }
      }
      None
    }
    Bin(And, a, b) => {
      match
        check_temporal_expr(
          ctx,
          var_names,
          states,
          adj,
          init_ids,
          all_ids,
          prop_name,
          a,
          fairness,
          depth + 1,
        ) {
        Some(res) => return Some(res)
        None => ()
      }
      check_temporal_expr(
        ctx,
        var_names,
        states,
        adj,
        init_ids,
        all_ids,
        prop_name,
        b,
        fairness,
        depth + 1,
      )
    }
    ConjList(items) => {
      for it in items {
        match
          check_temporal_expr(
            ctx,
            var_names,
            states,
            adj,
            init_ids,
            all_ids,
            prop_name,
            it,
            fairness,
            depth + 1,
          ) {
          Some(res) => return Some(res)
          None => ()
        }
      }
      None
    }
    Ident(alias_name) =>
      match ctx.lookup_op(alias_name) {
        Some(d) if d.params.is_empty() =>
          check_temporal_expr(
            ctx,
            var_names,
            states,
            adj,
            init_ids,
            all_ids,
            prop_name,
            d.body,
            fairness,
            depth + 1,
          )
        _ => {
          for i = 0; i < n; i = i + 1 {
            if !eval_state_pred_ctx(ctx, states[i].vals, expr, prop_name) {
              let trace = reconstruct_bfs_trace(var_names, states, i)
              return Some((prop_name, trace, None, i))
            }
          }
          None
        }
      }
    // []<>Q (infinitely often Q)
    Unary(Always, Unary(Eventually, q)) => {
      let q_holds : Array[Bool] = Array::make(n, false)
      for i = 0; i < n; i = i + 1 {
        q_holds[i] = eval_state_pred_ctx(ctx, states[i].vals, q, prop_name)
      }
      match
        find_avoidance_lasso(var_names, states, adj, all_ids, q_holds, fairness) {
        Some((trace, loop_idx, anchor)) =>
          Some((prop_name, trace, loop_idx, anchor))
        None => None
      }
    }
    // [](P => <>Q) is equivalent to P ~> Q
    Unary(Always, Bin(Implies, p, Unary(Eventually, q))) | Bin(LeadsTo, p, q) => {
      let triggers : Array[Int32] = []
      let q_holds : Array[Bool] = Array::make(n, false)
      for i = 0; i < n; i = i + 1 {
        q_holds[i] = eval_state_pred_ctx(ctx, states[i].vals, q, prop_name)
        if !q_holds[i] && eval_state_pred_ctx(ctx, states[i].vals, p, prop_name) {
          triggers.push(i)
        }
      }
      match
        find_avoidance_lasso(
          var_names, states, adj, triggers, q_holds, fairness,
        ) {
        Some((trace, loop_idx, anchor)) =>
          Some((prop_name, trace, loop_idx, anchor))
        None => None
      }
    }
    // <>Q
    Unary(Eventually, q) => {
      let q_holds : Array[Bool] = Array::make(n, false)
      for i = 0; i < n; i = i + 1 {
        q_holds[i] = eval_state_pred_ctx(ctx, states[i].vals, q, prop_name)
      }
      match
        find_avoidance_lasso(
          var_names, states, adj, init_ids, q_holds, fairness,
        ) {
        Some((trace, loop_idx, anchor)) =>
          Some((prop_name, trace, loop_idx, anchor))
        None => None
      }
    }
    // []P (box invariant property)
    Unary(Always, p) => {
      for i = 0; i < n; i = i + 1 {
        if !eval_state_pred_ctx(ctx, states[i].vals, p, prop_name) {
          let trace = reconstruct_bfs_trace(var_names, states, i)
          return Some((prop_name, trace, None, i))
        }
      }
      None
    }
    // Fallback: state predicate evaluated on all reachable states
    other => {
      for i = 0; i < n; i = i + 1 {
        if !eval_state_pred_ctx(ctx, states[i].vals, other, prop_name) {
          let trace = reconstruct_bfs_trace(var_names, states, i)
          return Some((prop_name, trace, None, i))
        }
      }
      None
    }
  }
}

///|
/// Check temporal safety/liveness properties (`[]P`, `<>P`, `[]<>P`, `P ~> Q`, `\A x \in S : ...`)
/// over the complete finite state graph using Emerson-Lei iterative SCC fairness pruning.
fn check_liveness_properties(
  ctx : EvalCtx,
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  fp_to_id : Map[(UInt64, UInt64), Int32],
  sym_spec : SymmetrySpec,
  symmetry_applied : Bool,
  properties : Array[String],
  fairness : Array[FairnessClause],
) -> (String, Array[TraceStep], Int32?, Int32)? raise TlaError {
  let n = states.length()
  let init_ids : Array[Int32] = []
  let all_ids : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    all_ids.push(i)
    if states[i].is_init {
      init_ids.push(i)
    }
  }
  let prepared = prepare_fairness(
    ctx, var_names, states, fp_to_id, sym_spec, symmetry_applied, fairness,
  )

  for prop_name in properties {
    let def = match ctx.lookup_op(prop_name) {
      Some(d) => d
      None => raise CheckError("PROPERTY '\{prop_name}' not found")
    }
    match
      check_temporal_expr(
        ctx,
        var_names,
        states,
        adj,
        init_ids,
        all_ids,
        prop_name,
        def.body,
        prepared,
        0,
      ) {
      Some(res) => return Some(res)
      None => ()
    }
  }
  None
}
