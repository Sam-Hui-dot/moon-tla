///|
fn is_cfg_section_kw(word : String) -> Bool {
  match word {
    "SPECIFICATION"
    | "INIT"
    | "NEXT"
    | "INVARIANT"
    | "INVARIANTS"
    | "PROPERTY"
    | "PROPERTIES"
    | "CONSTANT"
    | "CONSTANTS"
    | "SYMMETRY"
    | "CHECK_DEADLOCK"
    | "CONSTRAINT"
    | "CONSTRAINTS"
    | "ACTION_CONSTRAINT"
    | "ACTION_CONSTRAINTS"
    | "VIEW" => true
    _ => false
  }
}

///|
fn parse_cfg_value(p : Parser) -> CfgValue raise TlaError {
  let tok = p.peek()
  match tok.kind {
    Int(v) => {
      let _ = p.advance()
      CfgInt(v)
    }
    Minus => {
      let _ = p.advance()
      match p.peek().kind {
        Int(v) => {
          let _ = p.advance()
          CfgInt(-v)
        }
        _ =>
          raise CfgError(
            "expected integer after '-' in .cfg at line \{tok.line}:\{tok.col}",
          )
      }
    }
    Str(s) => {
      let _ = p.advance()
      CfgStr(s)
    }
    Ident("TRUE") => {
      let _ = p.advance()
      CfgBool(true)
    }
    Ident("FALSE") => {
      let _ = p.advance()
      CfgBool(false)
    }
    Ident(name) => {
      let _ = p.advance()
      CfgModel(name)
    }
    LBrace => {
      let _ = p.advance()
      let items : Array[CfgValue] = []
      if p.peek().kind != RBrace {
        items.push(parse_cfg_value(p))
        while p.peek().kind == Comma {
          let _ = p.advance()
          items.push(parse_cfg_value(p))
        }
      }
      p.expect_kind(RBrace, "'}'")
      CfgSet(items)
    }
    _ =>
      raise CfgError(
        "unexpected token \{@debug.to_string(tok.kind)} in .cfg value at line \{tok.line}:\{tok.col}",
      )
  }
}

///|
/// Parse a standard TLC `.cfg` file string into `TlaConfig`.
pub fn parse_cfg(src : String) -> TlaConfig raise TlaError {
  let tokens = lex_tla(src)
  let p : Parser = { tokens, pos: 0, }
  let mut specification : String? = None
  let mut init : String? = None
  let mut next : String? = None
  let invariants : Array[String] = []
  let properties : Array[String] = []
  let constants : Array[(String, CfgValue)] = []
  let overrides : Array[(String, String)] = []
  let mut symmetry : String? = None
  let mut check_deadlock = true

  while p.peek().kind != Eof {
    let tok = p.peek()
    match tok.kind {
      Ident("SPECIFICATION") => {
        let _ = p.advance()
        specification = Some(p.expect_ident())
      }
      Ident("INIT") => {
        let _ = p.advance()
        init = Some(p.expect_ident())
      }
      Ident("NEXT") => {
        let _ = p.advance()
        next = Some(p.expect_ident())
      }
      Ident("INVARIANT") | Ident("INVARIANTS") => {
        let _ = p.advance()
        while p.peek().kind != Eof {
          match p.peek().kind {
            Ident(w) if !is_cfg_section_kw(w) => {
              let _ = p.advance()
              invariants.push(w)
            }
            _ => break
          }
        }
      }
      Ident("PROPERTY") | Ident("PROPERTIES") => {
        let _ = p.advance()
        while p.peek().kind != Eof {
          match p.peek().kind {
            Ident(w) if !is_cfg_section_kw(w) => {
              let _ = p.advance()
              properties.push(w)
            }
            _ => break
          }
        }
      }
      Ident("SYMMETRY") => {
        let _ = p.advance()
        symmetry = Some(p.expect_ident())
      }
      Ident("CHECK_DEADLOCK") => {
        let _ = p.advance()
        match p.peek().kind {
          Ident("TRUE") => {
            let _ = p.advance()
            check_deadlock = true
          }
          Ident("FALSE") => {
            let _ = p.advance()
            check_deadlock = false
          }
          _ =>
            raise CfgError(
              "CHECK_DEADLOCK expects TRUE or FALSE at line \{tok.line}",
            )
        }
      }
      Ident("CONSTANT") | Ident("CONSTANTS") => {
        let _ = p.advance()
        while p.peek().kind != Eof {
          match p.peek().kind {
            Ident(w) if !is_cfg_section_kw(w) => {
              let _ = p.advance()
              if p.peek().kind == Eq {
                let _ = p.advance()
                let v = parse_cfg_value(p)
                constants.push((w, v))
              } else if p.peek().kind == Lt && p.peek_at(1).kind == Minus {
                let _ = p.advance()
                let _ = p.advance()
                let target = p.expect_ident()
                overrides.push((w, target))
              } else {
                constants.push((w, CfgModel(w)))
              }
            }
            _ => break
          }
        }
      }
      _ =>
        raise CfgError(
          "unexpected token \{@debug.to_string(tok.kind)} in .cfg at line \{tok.line}:\{tok.col}",
        )
    }
  }

  {
    specification,
    init,
    next,
    invariants,
    properties,
    constants,
    overrides,
    symmetry,
    check_deadlock,
  }
}

///|
/// Construct a default empty `TlaConfig` for programmatic model checking.
pub fn default_config(
  init~ : String = "Init",
  next~ : String = "Next",
  invariants~ : Array[String] = [],
  properties~ : Array[String] = [],
  constants~ : Array[(String, CfgValue)] = [],
  check_deadlock~ : Bool = true,
) -> TlaConfig {
  {
    specification: None,
    init: Some(init),
    next: Some(next),
    invariants,
    properties,
    constants,
    overrides: [],
    symmetry: None,
    check_deadlock,
  }
}
