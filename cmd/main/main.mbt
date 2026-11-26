///|
let usage : String =
  #|moon-tla check <SPEC.tla> [--cfg <FILE.cfg>] [--init INIT] [--next NEXT] [--inv INV]... [--prop PROP]... [--no-deadlock] [--max-states N] [--max-graph-nodes N] [--format text|json|md|trace-svg|graph-svg] [--out FILE] [--exit-zero]
  #|moon-tla parse <SPEC.tla> [--format text|json]
  #|moon-tla eval <EXPR>

///|
fn parse_int_arg(flag : String, raw : String) -> Int32 raise @moon-tla.TlaError {
  @string.parse_int(raw) catch {
    _ =>
      raise @moon-tla.TlaError::InvalidInput(
        "invalid integer for \{flag}: \{raw}",
      )
  }
}

///|
fn next_flag_value(
  args : Array[String],
  index : Int32,
  flag : String,
) -> String raise @moon-tla.TlaError {
  guard index + 1 < args.length() else {
    raise @moon-tla.TlaError::InvalidInput("\{flag} requires a value")
  }
  args[index + 1]
}

///|
async fn emit_text(content : String, out_path : String?) -> Unit {
  match out_path {
    Some(p) => @fs.write_file(p, content, create_mode=CreateOrTruncate)
    None => println(content)
  }
}

///|
async fn cmd_check(args : Array[String]) -> Int32 {
  guard args.length() >= 2 else {
    raise @moon-tla.TlaError::InvalidInput(usage)
  }
  let tla_path = args[1]
  let mut cfg_path : String? = None
  let mut init_ov : String? = None
  let mut next_ov : String? = None
  let extra_invs : Array[String] = []
  let extra_props : Array[String] = []
  let mut no_deadlock = false
  let mut max_states = 200000
  let mut max_graph_nodes = 80
  let mut format = "text"
  let mut out_path : String? = None
  let mut exit_zero = false

  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--cfg" => {
        cfg_path = Some(next_flag_value(args, i, "--cfg"))
        i += 2
      }
      "--init" => {
        init_ov = Some(next_flag_value(args, i, "--init"))
        i += 2
      }
      "--next" => {
        next_ov = Some(next_flag_value(args, i, "--next"))
        i += 2
      }
      "--inv" => {
        extra_invs.push(next_flag_value(args, i, "--inv"))
        i += 2
      }
      "--prop" => {
        extra_props.push(next_flag_value(args, i, "--prop"))
        i += 2
      }
      "--no-deadlock" => {
        no_deadlock = true
        i += 1
      }
      "--max-states" => {
        max_states = parse_int_arg(
          "--max-states",
          next_flag_value(args, i, "--max-states"),
        )
        i += 2
      }
      "--max-graph-nodes" => {
        max_graph_nodes = parse_int_arg(
          "--max-graph-nodes",
          next_flag_value(args, i, "--max-graph-nodes"),
        )
        i += 2
      }
      "--format" => {
        format = next_flag_value(args, i, "--format")
        i += 2
      }
      "--out" | "-o" => {
        out_path = Some(next_flag_value(args, i, args[i]))
        i += 2
      }
      "--exit-zero" => {
        exit_zero = true
        i += 1
      }
      other =>
        raise @moon-tla.TlaError::InvalidInput("unknown option: \{other}")
    }
  }

  let tla_src = @fs.read_file(tla_path).text()
  let tla_mod = @moon-tla.parse_module(tla_src)

  let base_cfg = match cfg_path {
    Some(cp) => @moon-tla.parse_cfg(@fs.read_file(cp).text())
    None => @moon-tla.default_config()
  }
  let invs = base_cfg.invariants.copy()
  for inv in extra_invs {
    invs.push(inv)
  }
  let props = base_cfg.properties.copy()
  for prop in extra_props {
    props.push(prop)
  }
  let cfg : @moon-tla.TlaConfig = {
    specification: base_cfg.specification,
    init: match init_ov {
      Some(v) => Some(v)
      None => base_cfg.init
    },
    next: match next_ov {
      Some(v) => Some(v)
      None => base_cfg.next
    },
    invariants: invs,
    properties: props,
    constants: base_cfg.constants,
    overrides: base_cfg.overrides,
    symmetry: base_cfg.symmetry,
    check_deadlock: if no_deadlock {
      false
    } else {
      base_cfg.check_deadlock
    },
  }

  let opts = @moon-tla.check_options(max_states~, max_graph_nodes~)
  let result = @moon-tla.check_module(tla_mod, cfg, options=opts)
  let rendered = match format {
    "text" => @moon-tla.render_result_text(result)
    "json" => @json.ToJson::to_json(result).stringify()
    "md" | "markdown" => @moon-tla.render_result_markdown(result)
    "trace-svg" | "svg" => @moon-tla.render_trace_svg(result)
    "graph-svg" => @moon-tla.render_state_graph_svg(result)
    _ =>
      raise @moon-tla.TlaError::InvalidInput("unsupported --format: \{format}")
  }
  emit_text(rendered, out_path)
  if exit_zero || result.status == Ok {
    0
  } else {
    1
  }
}

///|
async fn cmd_parse(args : Array[String]) -> Int32 {
  guard args.length() >= 2 else {
    raise @moon-tla.TlaError::InvalidInput(usage)
  }
  let tla_path = args[1]
  let mut format = "text"
  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--format" => {
        format = next_flag_value(args, i, "--format")
        i += 2
      }
      other =>
        raise @moon-tla.TlaError::InvalidInput("unknown option: \{other}")
    }
  }
  let tla_src = @fs.read_file(tla_path).text()
  let tla_mod = @moon-tla.parse_module(tla_src)
  let def_names : Array[String] = []
  for d in tla_mod.defs {
    def_names.push(d.name)
  }
  match format {
    "json" =>
      println(
        @json.Json::object({
          "module": @json.ToJson::to_json(tla_mod.name),
          "extends": @json.ToJson::to_json(tla_mod.extends),
          "constants": @json.ToJson::to_json(tla_mod.constants),
          "variables": @json.ToJson::to_json(tla_mod.variables),
          "operators": @json.ToJson::to_json(def_names),
        }).stringify(),
      )
    _ => {
      let exts = tla_mod.extends.join(", ")
      let consts = tla_mod.constants.join(", ")
      let vars = tla_mod.variables.join(", ")
      let ops = def_names.join(", ")
      println("Module: \{tla_mod.name}")
      println("Extends: \{exts}")
      println("Constants: \{consts}")
      println("Variables: \{vars}")
      println("Operators (\{def_names.length()}): \{ops}")
    }
  }
  0
}

///|
fn cmd_eval(args : Array[String]) -> Int32 raise @moon-tla.TlaError {
  guard args.length() >= 2 else {
    raise @moon-tla.TlaError::InvalidInput(usage)
  }
  let expr = @moon-tla.parse_expr_str(args[1])
  let val = @moon-tla.eval_expr_standalone(expr)
  println(@moon-tla.format_val(val))
  0
}

///|
async fn run(args : Array[String]) -> Int32 {
  match args.get(0) {
    Some("check") => cmd_check(args)
    Some("parse") => cmd_parse(args)
    Some("eval") => cmd_eval(args)
    _ => raise @moon-tla.TlaError::InvalidInput(usage)
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    println(usage)
    return
  }
  let exit_code = match
    (@async.with_timeout_opt(120_000, () => run(args[1:].to_owned())) catch {
      error => {
        println(@moon-tla.error_message(error))
        Some(2)
      }
    }) {
    Some(code) => code
    None => {
      println("operation timed out after 120s")
      2
    }
  }
  @env.exit(exit_code)
}
