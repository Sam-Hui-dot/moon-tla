///|
fn xml_escape(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    match ch {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&#39;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn truncate_str(s : String, max_len : Int32) -> String {
  let chars = s.to_array()
  if chars.length() <= max_len {
    return s
  }
  let sb = StringBuilder()
  let lim = if max_len > 3 { max_len - 3 } else { max_len }
  for i = 0; i < lim; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.write_string("...")
  sb.to_string()
}

///|
fn status_palette(status : CheckStatus) -> (String, String, String) {
  match status {
    Ok => ("PASS", "#10b981", "#064e3b")
    InvariantViolation(_) => ("INVARIANT VIOLATION", "#f43f5e", "#4c0519")
    Deadlock => ("DEADLOCK", "#f59e0b", "#451a03")
    LivenessViolation(_) => ("LIVENESS VIOLATION", "#a855f7", "#3b0764")
    StateLimitReached(_) => ("STATE LIMIT", "#38bdf8", "#0c4a6e")
  }
}

///|
/// Render a native SVG counterexample sequence timeline with per-step variable diffs
/// (or a verification summary badge if no counterexample exists).
pub fn render_trace_svg(result : CheckResult) -> String {
  let width = 880
  let pad = 24
  let header_h = 84
  let (badge, accent, badge_bg) = status_palette(result.status)
  let sb = StringBuilder()

  if result.trace.is_empty() {
    let height = 230
    sb.write_string(
      "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-tla-trace\" width=\"\{width}\" height=\"\{height}\" viewBox=\"0 0 \{width} \{height}\">\n",
    )
    sb.write_string(
      "<rect width=\"\{width}\" height=\"\{height}\" rx=\"12\" fill=\"#0f172a\"/>\n",
    )
    sb.write_string(
      "<rect x=\"\{pad}\" y=\"\{pad}\" width=\"\{width - pad * 2}\" height=\"\{height - pad * 2}\" rx=\"10\" fill=\"#1e293b\" stroke=\"\{accent}\" stroke-width=\"1.5\"/>\n",
    )
    sb.write_string(
      "<rect x=\"42\" y=\"42\" width=\"110\" height=\"26\" rx=\"13\" fill=\"\{badge_bg}\" stroke=\"\{accent}\" stroke-width=\"1\"/>\n",
    )
    sb.write_string(
      "<text x=\"97\" y=\"59\" text-anchor=\"middle\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" font-weight=\"700\" fill=\"\{accent}\">\{badge}</text>\n",
    )
    sb.write_string(
      "<text x=\"166\" y=\"60\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"18\" font-weight=\"700\" fill=\"#f8fafc\">\{xml_escape(result.module_name)} — Verified Safe</text>\n",
    )
    sb.write_string(
      "<text x=\"42\" y=\"96\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"13\" fill=\"#cbd5e1\">\{xml_escape(result.status_text)}</text>\n",
    )
    sb.write_string(
      "<text x=\"42\" y=\"132\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"13\" fill=\"#94a3b8\">distinct_states=\{result.distinct_states}   diameter=\{result.diameter}   transitions=\{result.transitions}   generated=\{result.states_generated}</text>\n",
    )
    let invs = if result.invariants_checked.is_empty() {
      "(none)"
    } else {
      result.invariants_checked.join(", ")
    }
    let props = if result.properties_checked.is_empty() {
      "(none)"
    } else {
      result.properties_checked.join(", ")
    }
    sb.write_string(
      "<text x=\"42\" y=\"160\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#64748b\">invariants: \{xml_escape(truncate_str(invs, 78))}</text>\n",
    )
    sb.write_string(
      "<text x=\"42\" y=\"182\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#64748b\">properties: \{xml_escape(truncate_str(props, 78))}</text>\n",
    )
    sb.write_string("</svg>\n")
    return sb.to_string()
  }

  // Pre-compute heights of each step card
  let card_x = 32
  let card_w = if result.lasso_loop_start is Some(_) { 740 } else { 816 }
  let arrow_gap = 42
  let card_ys : Array[Int32] = []
  let card_hs : Array[Int32] = []
  let mut cur_y = header_h + 18
  for i = 0; i < result.trace.length(); i = i + 1 {
    let step = result.trace[i]
    let rows = if i == 0 {
      step.bindings.length()
    } else if step.diffs.is_empty() {
      1
    } else {
      step.diffs.length()
    }
    let h = 44 + rows * 20 + 12
    card_ys.push(cur_y)
    card_hs.push(h)
    cur_y = cur_y + h + arrow_gap
  }
  let total_h = cur_y + 12

  sb.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-tla-trace\" width=\"\{width}\" height=\"\{total_h}\" viewBox=\"0 0 \{width} \{total_h}\">\n",
  )
  sb.write_string(
    "<defs>\n  <marker id=\"tla-arrow\" viewBox=\"0 0 10 10\" refX=\"8\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\"><path d=\"M 0 1 L 10 5 L 0 9 z\" fill=\"#94a3b8\"/></marker>\n  <marker id=\"tla-loop-arrow\" viewBox=\"0 0 10 10\" refX=\"8\" refY=\"5\" markerWidth=\"8\" markerHeight=\"8\" orient=\"auto-start-reverse\"><path d=\"M 0 1 L 10 5 L 0 9 z\" fill=\"#a855f7\"/></marker>\n</defs>\n",
  )
  sb.write_string(
    "<rect width=\"\{width}\" height=\"\{total_h}\" rx=\"12\" fill=\"#0f172a\"/>\n",
  )

  // Header bar
  sb.write_string(
    "<rect x=\"0\" y=\"0\" width=\"\{width}\" height=\"\{header_h}\" rx=\"12\" fill=\"#1e293b\"/>\n",
  )
  sb.write_string(
    "<rect x=\"0\" y=\"\{header_h - 12}\" width=\"\{width}\" height=\"12\" fill=\"#1e293b\"/>\n",
  )
  sb.write_string(
    "<line x1=\"0\" y1=\"\{header_h}\" x2=\"\{width}\" y2=\"\{header_h}\" stroke=\"#334155\" stroke-width=\"1\"/>\n",
  )
  sb.write_string(
    "<rect x=\"24\" y=\"18\" width=\"176\" height=\"24\" rx=\"12\" fill=\"\{badge_bg}\" stroke=\"\{accent}\" stroke-width=\"1\"/>\n",
  )
  sb.write_string(
    "<text x=\"112\" y=\"34\" text-anchor=\"middle\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" font-weight=\"700\" fill=\"\{accent}\">\{badge}</text>\n",
  )
  sb.write_string(
    "<text x=\"214\" y=\"35\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"16\" font-weight=\"700\" fill=\"#f8fafc\">\{xml_escape(result.module_name)} — \{xml_escape(truncate_str(result.status_text, 56))}</text>\n",
  )
  sb.write_string(
    "<text x=\"24\" y=\"65\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#94a3b8\">trace=\{result.trace.length()} states (\{result.trace.length() - 1} steps)   distinct=\{result.distinct_states}   diameter=\{result.diameter}   transitions=\{result.transitions}</text>\n",
  )

  // Render cards and arrows
  let n_steps = result.trace.length()
  for i = 0; i < n_steps; i = i + 1 {
    let step = result.trace[i]
    let y = card_ys[i]
    let h = card_hs[i]
    let is_last = i + 1 == n_steps
    let is_loop_anchor = match result.lasso_loop_start {
      Some(ls) => ls == step.step
      None => false
    }
    let stroke = if is_last {
      accent
    } else if i == 0 {
      "#38bdf8"
    } else if is_loop_anchor {
      "#a855f7"
    } else {
      "#334155"
    }
    let fill = if is_last { "#1f1220" } else { "#1e293b" }
    let stroke_w = if is_last || i == 0 || is_loop_anchor { "1.8" } else { "1" }

    // Transition arrow from previous card
    if i > 0 {
      let prev_bottom = card_ys[i - 1] + card_hs[i - 1]
      let mid_x = card_x + 36
      let mid_y = prev_bottom + arrow_gap / 2 + 4
      sb.write_string(
        "<line x1=\"\{mid_x}\" y1=\"\{prev_bottom}\" x2=\"\{mid_x}\" y2=\"\{y - 4}\" stroke=\"#94a3b8\" stroke-width=\"1.8\" marker-end=\"url(#tla-arrow)\"/>\n",
      )
      sb.write_string(
        "<rect x=\"\{mid_x + 14}\" y=\"\{prev_bottom + 8}\" width=\"360\" height=\"24\" rx=\"6\" fill=\"#0b1220\" stroke=\"#334155\" stroke-width=\"1\"/>\n",
      )
      sb.write_string(
        "<text x=\"\{mid_x + 24}\" y=\"\{mid_y}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#38bdf8\">action: \{xml_escape(truncate_str(step.action, 40))}</text>\n",
      )
    }

    sb.write_string(
      "<rect x=\"\{card_x}\" y=\"\{y}\" width=\"\{card_w}\" height=\"\{h}\" rx=\"8\" fill=\"\{fill}\" stroke=\"\{stroke}\" stroke-width=\"\{stroke_w}\"/>\n",
    )
    let tag_text = if i == 0 {
      "INIT"
    } else if is_last {
      badge
    } else if is_loop_anchor {
      "LOOP START"
    } else {
      "STEP \{i}"
    }
    let tag_color = if i == 0 {
      "#38bdf8"
    } else if is_last {
      accent
    } else if is_loop_anchor {
      "#c084fc"
    } else {
      "#94a3b8"
    }
    sb.write_string(
      "<text x=\"\{card_x + 14}\" y=\"\{y + 24}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"13\" font-weight=\"700\" fill=\"#f8fafc\">State \{step.step}</text>\n",
    )
    sb.write_string(
      "<text x=\"\{card_x + 92}\" y=\"\{y + 24}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" font-weight=\"700\" fill=\"\{tag_color}\">[\{tag_text}]</text>\n",
    )
    sb.write_string(
      "<text x=\"\{card_x + card_w - 14}\" y=\"\{y + 24}\" text-anchor=\"end\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" fill=\"#64748b\">id=#\{step.state_id}</text>\n",
    )
    sb.write_string(
      "<line x1=\"\{card_x + 12}\" y1=\"\{y + 34}\" x2=\"\{card_x + card_w - 12}\" y2=\"\{y + 34}\" stroke=\"#334155\" stroke-width=\"1\"/>\n",
    )

    let mut row_y = y + 54
    if i == 0 {
      for b in step.bindings {
        let line = "\{b.name} = \{b.value}"
        sb.write_string(
          "<text x=\"\{card_x + 16}\" y=\"\{row_y}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#e2e8f0\">\{xml_escape(truncate_str(line, 92))}</text>\n",
        )
        row_y += 20
      }
    } else if step.diffs.is_empty() {
      sb.write_string(
        "<text x=\"\{card_x + 16}\" y=\"\{row_y}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" fill=\"#94a3b8\">(no variable changes — stutter step)</text>\n",
      )
    } else {
      for d in step.diffs {
        let diff_line = "\{d.name}: \{d.before}  ->  \{d.after}"
        sb.write_string(
          "<text x=\"\{card_x + 16}\" y=\"\{row_y}\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"12\" font-weight=\"600\" fill=\"#fda4af\">Δ \{xml_escape(truncate_str(diff_line, 90))}</text>\n",
        )
        row_y += 20
      }
    }
  }

  // Draw lasso loop-back arc if liveness cycle
  match result.lasso_loop_start {
    Some(loop_step) if loop_step >= 1 && loop_step <= n_steps => {
      let from_idx = n_steps - 1
      let to_idx = loop_step - 1
      let x0 = card_x + card_w
      let y0 = card_ys[from_idx] + card_hs[from_idx] / 2
      let y1 = card_ys[to_idx] + card_hs[to_idx] / 2
      let rail_x = width - 38
      sb.write_string(
        "<path d=\"M \{x0} \{y0} L \{rail_x} \{y0} L \{rail_x} \{y1} L \{x0 + 6} \{y1}\" fill=\"none\" stroke=\"#a855f7\" stroke-width=\"2.2\" stroke-dasharray=\"6 4\" marker-end=\"url(#tla-loop-arrow)\"/>\n",
      )
      let label_y = (y0 + y1) / 2
      sb.write_string(
        "<text x=\"\{rail_x - 8}\" y=\"\{label_y}\" text-anchor=\"end\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" font-weight=\"700\" fill=\"#c084fc\">CYCLE</text>\n",
      )
    }
    _ => ()
  }

  sb.write_string("</svg>\n")
  sb.to_string()
}

///|
/// Render a layered BFS state-space graph SVG highlighting initial states,
/// counterexample paths, and offending/deadlock states with hover snapshots.
pub fn render_state_graph_svg(result : CheckResult) -> String {
  let nodes = result.graph_nodes
  let edges = result.graph_edges
  if nodes.is_empty() {
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-tla-graph\" width=\"600\" height=\"120\"><rect width=\"600\" height=\"120\" rx=\"10\" fill=\"#0f172a\"/><text x=\"24\" y=\"64\" font-family=\"sans-serif\" font-size=\"14\" fill=\"#94a3b8\">No states to display</text></svg>\n"
  }

  let mut max_depth = 0
  for n in nodes {
    if n.depth > max_depth {
      max_depth = n.depth
    }
  }
  let layers : Array[Array[GraphNode]] = []
  for _d = 0; _d <= max_depth; _d = _d + 1 {
    layers.push([])
  }
  for n in nodes {
    layers[n.depth].push(n)
  }

  let mut max_layer_size = 1
  for layer in layers {
    if layer.length() > max_layer_size {
      max_layer_size = layer.length()
    }
  }

  let col_w = 150
  let row_h = 68
  let left_pad = 64
  let top_pad = 72
  let bottom_pad = 54
  let width = {
    let raw = left_pad * 2 + (max_depth + 1) * col_w
    if raw < 760 {
      760
    } else {
      raw
    }
  }
  let height = {
    let raw = top_pad + bottom_pad + max_layer_size * row_h
    if raw < 320 {
      320
    } else {
      raw
    }
  }

  let pos_x : Map[Int32, Int32] = Map([])
  let pos_y : Map[Int32, Int32] = Map([])
  let usable_h = height - top_pad - bottom_pad
  for d = 0; d <= max_depth; d = d + 1 {
    let layer = layers[d]
    let x = left_pad + d * col_w + col_w / 2
    let cnt = layer.length()
    for i = 0; i < cnt; i = i + 1 {
      let y = top_pad + usable_h * (i + 1) / (cnt + 1)
      pos_x.set(layer[i].id, x)
      pos_y.set(layer[i].id, y)
    }
  }

  let sb = StringBuilder()
  sb.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"moon-tla-graph\" width=\"\{width}\" height=\"\{height}\" viewBox=\"0 0 \{width} \{height}\">\n",
  )
  sb.write_string(
    "<defs>\n  <marker id=\"g-arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"6\" markerHeight=\"6\" orient=\"auto\"><path d=\"M 0 1 L 10 5 L 0 9 z\" fill=\"#475569\"/></marker>\n  <marker id=\"g-arrow-trace\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto\"><path d=\"M 0 1 L 10 5 L 0 9 z\" fill=\"#f43f5e\"/></marker>\n</defs>\n",
  )
  sb.write_string(
    "<rect width=\"\{width}\" height=\"\{height}\" rx=\"12\" fill=\"#0f172a\"/>\n",
  )
  let cap_note = if nodes.length() < result.distinct_states {
    "showing \{nodes.length()} / \{result.distinct_states} states (full trace preserved)"
  } else {
    "showing all \{nodes.length()} distinct states"
  }
  sb.write_string(
    "<text x=\"24\" y=\"30\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"15\" font-weight=\"700\" fill=\"#f8fafc\">\{xml_escape(result.module_name)} State-Space Graph (BFS Layers 0..\{max_depth})</text>\n",
  )
  sb.write_string(
    "<text x=\"24\" y=\"50\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" fill=\"#94a3b8\">\{cap_note}   diameter=\{result.diameter}   hover nodes for full state snapshot</text>\n",
  )

  // Draw non-trace edges first, then trace edges on top
  for pass = 0; pass < 2; pass = pass + 1 {
    let want_trace = pass == 1
    for e in edges {
      if e.is_on_trace != want_trace {
        continue
      }
      match
        (pos_x.get(e.from), pos_y.get(e.from), pos_x.get(e.to), pos_y.get(e.to)) {
        (Some(x1), Some(y1), Some(x2), Some(y2)) => {
          let stroke = if want_trace { "#f43f5e" } else { "#334155" }
          let sw = if want_trace { "2.4" } else { "1.1" }
          let marker = if want_trace {
            "url(#g-arrow-trace)"
          } else {
            "url(#g-arrow)"
          }
          if e.from == e.to {
            sb.write_string(
              "<path d=\"M \{x1 + 12} \{y1 - 16} C \{x1 + 36} \{y1 - 44}, \{x1 - 36} \{y1 - 44}, \{x1 - 12} \{y1 - 16}\" fill=\"none\" stroke=\"\{stroke}\" stroke-width=\"\{sw}\" marker-end=\"\{marker}\"><title>\{xml_escape(e.action)}</title></path>\n",
            )
          } else {
            let cx = (x1 + x2) / 2
            let cy = if x2 <= x1 { (y1 + y2) / 2 - 28 } else { (y1 + y2) / 2 }
            let dx = x2 - x1
            let dy = y2 - y1
            let ex = if dx > 20 {
              x2 - 20
            } else if dx < -20 {
              x2 + 20
            } else {
              x2
            }
            let ey = if dy > 18 {
              y2 - 14
            } else if dy < -18 {
              y2 + 14
            } else {
              y2
            }
            sb.write_string(
              "<path d=\"M \{x1} \{y1} Q \{cx} \{cy} \{ex} \{ey}\" fill=\"none\" stroke=\"\{stroke}\" stroke-width=\"\{sw}\" marker-end=\"\{marker}\"><title>\{xml_escape(e.action)}</title></path>\n",
            )
          }
        }
        _ => ()
      }
    }
  }

  // Draw nodes
  for n in nodes {
    match (pos_x.get(n.id), pos_y.get(n.id)) {
      (Some(x), Some(y)) => {
        let (fill, stroke) = if n.is_violation {
          ("#9f1239", "#fda4af")
        } else if n.is_init {
          ("#0369a1", "#7dd3fc")
        } else if n.is_on_trace {
          ("#881337", "#fb7185")
        } else {
          ("#1e293b", "#64748b")
        }
        if n.is_violation {
          sb.write_string(
            "<circle cx=\"\{x}\" cy=\"\{y}\" r=\"24\" fill=\"none\" stroke=\"#f43f5e\" stroke-width=\"1.5\" stroke-dasharray=\"4 3\"/>\n",
          )
        }
        sb.write_string("<g>\n")
        sb.write_string(
          "  <title>State #\{n.id} (depth \{n.depth})\n\{xml_escape(n.detail)}</title>\n",
        )
        sb.write_string(
          "  <circle cx=\"\{x}\" cy=\"\{y}\" r=\"18\" fill=\"\{fill}\" stroke=\"\{stroke}\" stroke-width=\"2\"/>\n",
        )
        sb.write_string(
          "  <text x=\"\{x}\" y=\"\{y + 4}\" text-anchor=\"middle\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"11\" font-weight=\"700\" fill=\"#f8fafc\">s\{n.id}</text>\n",
        )
        sb.write_string(
          "  <text x=\"\{x}\" y=\"\{y + 31}\" text-anchor=\"middle\" font-family=\"ui-monospace,SFMono-Regular,Menlo,monospace\" font-size=\"9\" fill=\"#94a3b8\">\{xml_escape(truncate_str(n.label, 22))}</text>\n",
        )
        sb.write_string("</g>\n")
      }
      _ => ()
    }
  }

  // Legend
  let ly = height - 18
  sb.write_string(
    "<circle cx=\"30\" cy=\"\{ly - 4}\" r=\"6\" fill=\"#0369a1\" stroke=\"#7dd3fc\" stroke-width=\"1.5\"/><text x=\"42\" y=\"\{ly}\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"11\" fill=\"#cbd5e1\">Init</text>\n",
  )
  sb.write_string(
    "<circle cx=\"92\" cy=\"\{ly - 4}\" r=\"6\" fill=\"#1e293b\" stroke=\"#64748b\" stroke-width=\"1.5\"/><text x=\"104\" y=\"\{ly}\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"11\" fill=\"#cbd5e1\">Reachable</text>\n",
  )
  sb.write_string(
    "<circle cx=\"184\" cy=\"\{ly - 4}\" r=\"6\" fill=\"#881337\" stroke=\"#fb7185\" stroke-width=\"1.5\"/><text x=\"196\" y=\"\{ly}\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"11\" fill=\"#cbd5e1\">Counterexample Path</text>\n",
  )
  sb.write_string(
    "<circle cx=\"338\" cy=\"\{ly - 4}\" r=\"6\" fill=\"#9f1239\" stroke=\"#fda4af\" stroke-width=\"1.5\"/><text x=\"350\" y=\"\{ly}\" font-family=\"ui-sans-serif,system-ui,sans-serif\" font-size=\"11\" fill=\"#cbd5e1\">Violation / Deadlock</text>\n",
  )
  sb.write_string("</svg>\n")
  sb.to_string()
}
