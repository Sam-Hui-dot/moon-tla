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
fn has_self_loop(adj : Array[Array[(Int32, String)]], v : Int32) -> Bool {
  for pair in adj[v] {
    if pair.0 == v {
      return true
    }
  }
  false
}

///|
fn has_non_stutter_succ(adj : Array[Array[(Int32, String)]], v : Int32) -> Bool {
  for pair in adj[v] {
    if pair.0 != v {
      return true
    }
  }
  false
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
/// Find shortest non-empty cycle from `anchor` back to `anchor` inside `in_scc`.
fn find_cycle_in_scc(
  n : Int32,
  adj : Array[Array[(Int32, String)]],
  in_scc : Array[Bool],
  anchor : Int32,
) -> Array[(Int32, String)] {
  // Check immediate self-loop first
  for pair in adj[anchor] {
    if pair.0 == anchor {
      return [(anchor, pair.1)]
    }
  }
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
    // Stuttering cycle on anchor itself
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
/// Check for an infinite execution avoiding `goal` starting from any state in `start_ids`.
fn find_avoidance_lasso(
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  start_ids : Array[Int32],
  goal_holds : Array[Bool],
  has_wf_next : Bool,
) -> (Array[TraceStep], Int32?, Int32)? {
  let n = states.length()
  let allowed : Array[Bool] = Array::make(n, false)
  for i = 0; i < n; i = i + 1 {
    allowed[i] = !goal_holds[i]
  }
  let sccs = tarjan_scc_masked(n, adj, allowed)
  let bad_target : Array[Bool] = Array::make(n, false)
  let scc_of : Array[Int32] = Array::make(n, -1)
  for ci = 0; ci < sccs.length(); ci = ci + 1 {
    let comp = sccs[ci]
    let is_nontrivial = comp.length() >= 2 ||
      (comp.length() == 1 && has_self_loop(adj, comp[0]))
    let can_stutter_forever = comp.length() == 1 &&
      (!has_wf_next || !has_non_stutter_succ(adj, comp[0]))
    if is_nontrivial || can_stutter_forever {
      for v in comp {
        bad_target[v] = true
        scc_of[v] = ci
      }
    }
  }
  match bfs_path_masked(n, adj, allowed, start_ids, bad_target) {
    None => None
    Some(suffix) => {
      let start_id = suffix[0].0
      let anchor = suffix[suffix.length() - 1].0
      // Prefix from initial state to `start_id` via BFS parent pointers
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
      let loop_step = combined.length() // 1-based step index of `anchor`
      let in_scc : Array[Bool] = Array::make(n, false)
      let ci = scc_of[anchor]
      if ci >= 0 {
        for v in sccs[ci] {
          in_scc[v] = true
        }
      } else {
        in_scc[anchor] = true
      }
      let cycle = find_cycle_in_scc(n, adj, in_scc, anchor)
      for step in cycle {
        combined.push(step)
      }
      let trace = build_trace_from_ids(var_names, states, combined)
      Some((trace, Some(loop_step), anchor))
    }
  }
}

///|
/// Check temporal safety/liveness properties (`[]P`, `<>P`, `P ~> Q`) over the
/// complete finite state graph using Tarjan SCC cycle detection.
fn check_liveness_properties(
  ctx : EvalCtx,
  var_names : Array[String],
  states : Array[StoredState],
  adj : Array[Array[(Int32, String)]],
  properties : Array[String],
  has_wf_next : Bool,
) -> (String, Array[TraceStep], Int32?, Int32)? raise TlaError {
  let n = states.length()
  let init_ids : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    if states[i].is_init {
      init_ids.push(i)
    }
  }

  for prop_name in properties {
    let def = match ctx.lookup_op(prop_name) {
      Some(d) => d
      None => raise CheckError("PROPERTY '\{prop_name}' not found")
    }
    match def.body {
      // [](P => <>Q) is equivalent to P ~> Q
      Unary(Always, Bin(Implies, p, Unary(Eventually, q))) => {
        let triggers : Array[Int32] = []
        let q_holds : Array[Bool] = Array::make(n, false)
        for i = 0; i < n; i = i + 1 {
          q_holds[i] = eval_state_pred(ctx, states[i].vals, q, prop_name)
          if !q_holds[i] && eval_state_pred(ctx, states[i].vals, p, prop_name) {
            triggers.push(i)
          }
        }
        match
          find_avoidance_lasso(
            var_names, states, adj, triggers, q_holds, has_wf_next,
          ) {
          Some((trace, loop_idx, anchor)) =>
            return Some((prop_name, trace, loop_idx, anchor))
          None => ()
        }
      }
      // P ~> Q
      Bin(LeadsTo, p, q) => {
        let triggers : Array[Int32] = []
        let q_holds : Array[Bool] = Array::make(n, false)
        for i = 0; i < n; i = i + 1 {
          q_holds[i] = eval_state_pred(ctx, states[i].vals, q, prop_name)
          if !q_holds[i] && eval_state_pred(ctx, states[i].vals, p, prop_name) {
            triggers.push(i)
          }
        }
        match
          find_avoidance_lasso(
            var_names, states, adj, triggers, q_holds, has_wf_next,
          ) {
          Some((trace, loop_idx, anchor)) =>
            return Some((prop_name, trace, loop_idx, anchor))
          None => ()
        }
      }
      // <>Q
      Unary(Eventually, q) => {
        let q_holds : Array[Bool] = Array::make(n, false)
        for i = 0; i < n; i = i + 1 {
          q_holds[i] = eval_state_pred(ctx, states[i].vals, q, prop_name)
        }
        match
          find_avoidance_lasso(
            var_names, states, adj, init_ids, q_holds, has_wf_next,
          ) {
          Some((trace, loop_idx, anchor)) =>
            return Some((prop_name, trace, loop_idx, anchor))
          None => ()
        }
      }
      // []P (box invariant property)
      Unary(Always, p) =>
        for i = 0; i < n; i = i + 1 {
          if !eval_state_pred(ctx, states[i].vals, p, prop_name) {
            let trace = reconstruct_bfs_trace(var_names, states, i)
            return Some((prop_name, trace, None, i))
          }
        }
      // Fallback: state predicate evaluated on all reachable states
      other =>
        for i = 0; i < n; i = i + 1 {
          if !eval_state_pred(ctx, states[i].vals, other, prop_name) {
            let trace = reconstruct_bfs_trace(var_names, states, i)
            return Some((prop_name, trace, None, i))
          }
        }
    }
  }
  None
}
