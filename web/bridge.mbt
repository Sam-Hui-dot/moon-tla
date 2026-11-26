///|
fn json_err(err : Error) -> String {
  @json.Json::object({
    "ok": @json.ToJson::to_json(false),
    "error": @json.ToJson::to_json(@moon-tla.error_message(err)),
  }).stringify()
}

///|
/// Parse and model-check a `.tla` + `.cfg` pair in the browser, returning JSON
/// with full verdict, metrics, counterexample trace, native SVGs, and reports.
pub fn check_spec_json(
  tla_src : String,
  cfg_src : String,
  max_states : Int32,
  max_graph_nodes : Int32,
  deadlock_mode : Int32,
  symmetry_mode : Int32,
) -> String {
  try {
    let dl_ov : Bool? = if deadlock_mode < 0 {
      None
    } else {
      Some(deadlock_mode != 0)
    }
    let opts = @moon-tla.check_options(
      max_states~,
      max_graph_nodes~,
      check_deadlock=dl_ov,
      use_symmetry=symmetry_mode != 0,
    )
    let result = @moon-tla.check_spec_sources(tla_src, cfg_src, options=opts)
    let trace_svg = @moon-tla.render_trace_svg(result)
    let graph_svg = @moon-tla.render_state_graph_svg(result)
    let text = @moon-tla.render_result_text(result)
    let markdown = @moon-tla.render_result_markdown(result)
    @json.Json::object({
      "ok": @json.ToJson::to_json(true),
      "result": @json.ToJson::to_json(result),
      "trace_svg": @json.ToJson::to_json(trace_svg),
      "graph_svg": @json.ToJson::to_json(graph_svg),
      "text": @json.ToJson::to_json(text),
      "markdown": @json.ToJson::to_json(markdown),
    }).stringify()
  } catch {
    err => json_err(err)
  }
}

///|
/// Parse a `.tla` module and return its declared constants, variables, and operators.
pub fn parse_module_json(tla_src : String) -> String {
  try {
    let m = @moon-tla.parse_module(tla_src)
    let ops : Array[String] = []
    for d in m.defs {
      ops.push(d.name)
    }
    @json.Json::object({
      "ok": @json.ToJson::to_json(true),
      "module": @json.ToJson::to_json(m.name),
      "extends": @json.ToJson::to_json(m.extends),
      "constants": @json.ToJson::to_json(m.constants),
      "variables": @json.ToJson::to_json(m.variables),
      "operators": @json.ToJson::to_json(ops),
    }).stringify()
  } catch {
    err => json_err(err)
  }
}

///|
/// Evaluate a standalone TLA+ expression string in the browser.
pub fn eval_expr_json(expr_src : String) -> String {
  try {
    let e = @moon-tla.parse_expr_str(expr_src)
    let v = @moon-tla.eval_expr_standalone(e)
    @json.Json::object({
      "ok": @json.ToJson::to_json(true),
      "value": @json.ToJson::to_json(@moon-tla.format_val(v)),
    }).stringify()
  } catch {
    err => json_err(err)
  }
}

///|
extern "js" fn register_browser_api(
  check_fn : (String, String, Int32, Int32, Int32, Int32) -> String,
  parse_fn : (String) -> String,
  eval_fn : (String) -> String,
) -> Unit =
  #|(checkFn, parseFn, evalFn) => {
  #|  globalThis.MoonTla = {
  #|    checkSpec: (tla, cfg, opts = {}) => {
  #|      const dl = typeof opts.checkDeadlock === "boolean" ? (opts.checkDeadlock ? 1 : 0) : -1;
  #|      const sym = opts.useSymmetry === false ? 0 : 1;
  #|      return JSON.parse(checkFn(tla, cfg, opts.maxStates || 100000, opts.maxGraphNodes || 80, dl, sym));
  #|    },
  #|    parseModule: (tla) => JSON.parse(parseFn(tla)),
  #|    evalExpr: (expr) => JSON.parse(evalFn(expr)),
  #|  };
  #|}

///|
fn main {
  register_browser_api(check_spec_json, parse_module_json, eval_expr_json)
}
