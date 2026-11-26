///|
/// Render a TLC-compatible plain-text diagnostic report for terminal output.
pub fn render_result_text(result : CheckResult) -> String {
  let sb = StringBuilder()
  sb.write_string("Module: \{result.module_name}\n")
  sb.write_string("Status: \{result.status_text}\n")
  sb.write_string(
    "Stats:  distinct_states=\{result.distinct_states}, states_generated=\{result.states_generated}, diameter=\{result.diameter}, transitions=\{result.transitions}\n",
  )
  if !result.invariants_checked.is_empty() {
    let invs = result.invariants_checked.join(", ")
    sb.write_string("Invariants: \{invs}\n")
  }
  if !result.properties_checked.is_empty() {
    let props = result.properties_checked.join(", ")
    sb.write_string("Properties: \{props}\n")
  }
  if !result.trace.is_empty() {
    sb.write_string(
      "\nCounterexample Trace (\{result.trace.length()} states):\n",
    )
    for step in result.trace {
      sb.write_string("State \{step.step}: <\{step.action}>\n")
      for b in step.bindings {
        sb.write_string("  /\\ \{b.name} = \{b.value}\n")
      }
      if !step.diffs.is_empty() {
        sb.write_string("  [diff] ")
        for i = 0; i < step.diffs.length(); i = i + 1 {
          if i > 0 {
            sb.write_string("; ")
          }
          let d = step.diffs[i]
          sb.write_string("\{d.name}: \{d.before} -> \{d.after}")
        }
        sb.write_char('\n')
      }
    }
    match result.lasso_loop_start {
      Some(ls) => sb.write_string("Back to State \{ls} (infinite cycle)\n")
      None => ()
    }
  }
  sb.to_string()
}

///|
/// Render a GitHub-flavored Markdown report summarizing model-checking stats and any counterexample trace.
pub fn render_result_markdown(result : CheckResult) -> String {
  let sb = StringBuilder()
  sb.write_string("# moon-tla Report: `\{result.module_name}`\n\n")
  sb.write_string("- **Status**: \{result.status_text}\n")
  sb.write_string("- **Distinct States**: `\{result.distinct_states}`\n")
  sb.write_string("- **States Generated**: `\{result.states_generated}`\n")
  sb.write_string("- **Graph Diameter**: `\{result.diameter}`\n")
  sb.write_string("- **Transitions**: `\{result.transitions}`\n")
  if !result.invariants_checked.is_empty() {
    let invs = result.invariants_checked.join(", ")
    sb.write_string("- **Invariants**: `\{invs}`\n")
  }
  if !result.properties_checked.is_empty() {
    let props = result.properties_checked.join(", ")
    sb.write_string("- **Properties**: `\{props}`\n")
  }
  if !result.trace.is_empty() {
    sb.write_string("\n## Counterexample Trace\n\n")
    sb.write_string("| Step | Action | Changed Variables | Full State |\n")
    sb.write_string("| ---: | --- | --- | --- |\n")
    for step in result.trace {
      let diff_sb = StringBuilder()
      if step.step == 1 {
        diff_sb.write_string("*(initial)*")
      } else if step.diffs.is_empty() {
        diff_sb.write_string("*(stutter)*")
      } else {
        for i = 0; i < step.diffs.length(); i = i + 1 {
          if i > 0 {
            diff_sb.write_string("; ")
          }
          let d = step.diffs[i]
          diff_sb.write_string("`\{d.name}`: `\{d.before}` -> `\{d.after}`")
        }
      }
      let state_sb = StringBuilder()
      for i = 0; i < step.bindings.length(); i = i + 1 {
        if i > 0 {
          state_sb.write_string(", ")
        }
        let b = step.bindings[i]
        state_sb.write_string("`\{b.name}=\{b.value}`")
      }
      sb.write_string(
        "| \{step.step} | `\{step.action}` | \{diff_sb.to_string()} | \{state_sb.to_string()} |\n",
      )
    }
    match result.lasso_loop_start {
      Some(ls) =>
        sb.write_string("\n> Lasso cycle returns to **State \{ls}**.\n")
      None => ()
    }
  }
  sb.to_string()
}
