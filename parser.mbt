///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int32
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::peek_at(self : Parser, offset : Int32) -> Token {
  let idx = self.pos + offset
  if idx >= 0 && idx < self.tokens.length() {
    self.tokens[idx]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.peek()
  if self.pos + 1 < self.tokens.length() {
    self.pos += 1
  }
  t
}

///|
fn Parser::is_kw(self : Parser, word : String) -> Bool {
  match self.peek().kind {
    Ident(s) => s == word
    _ => false
  }
}

///|
fn Parser::expect_kind(
  self : Parser,
  expected : TokKind,
  label : String,
) -> Unit raise TlaError {
  let tok = self.peek()
  if tok.kind == expected {
    let _ = self.advance()
  } else {
    raise ParseError(
      "expected \{label} at line \{tok.line}:\{tok.col}, got \{@debug.to_string(tok.kind)}",
    )
  }
}

///|
fn Parser::expect_kw(self : Parser, word : String) -> Unit raise TlaError {
  let tok = self.peek()
  match tok.kind {
    Ident(s) if s == word => {
      let _ = self.advance()
    }
    _ =>
      raise ParseError(
        "expected keyword '\{word}' at line \{tok.line}:\{tok.col}, got \{@debug.to_string(tok.kind)}",
      )
  }
}

///|
fn Parser::expect_ident(self : Parser) -> String raise TlaError {
  let tok = self.peek()
  match tok.kind {
    Ident(s) => {
      let _ = self.advance()
      s
    }
    _ =>
      raise ParseError(
        "expected identifier at line \{tok.line}:\{tok.col}, got \{@debug.to_string(tok.kind)}",
      )
  }
}

///|
fn is_reserved_terminator(word : String) -> Bool {
  match word {
    "THEN"
    | "ELSE"
    | "IN"
    | "OTHER"
    | "EXCEPT"
    | "MODULE"
    | "EXTENDS"
    | "CONSTANT"
    | "CONSTANTS"
    | "VARIABLE"
    | "VARIABLES"
    | "LOCAL"
    | "ASSUME"
    | "ASSUMPTION"
    | "THEOREM"
    | "LEMMA"
    | "PROOF"
    | "QED" => true
    _ => false
  }
}

///|
/// Strip optional leading prose before `---- MODULE` and trailing prose after `====`
/// while preserving 1-based line numbers for accurate diagnostics.
fn slice_module_source(src : String) -> String {
  let lines : Array[String] = []
  let cur = StringBuilder()
  for ch in src {
    if ch == '\n' {
      lines.push(cur.to_string())
      cur.reset()
    } else if ch != '\r' {
      cur.write_char(ch)
    }
  }
  lines.push(cur.to_string())

  let mut start_line = -1
  let mut end_line = lines.length()
  for idx = 0; idx < lines.length(); idx = idx + 1 {
    let trimmed = lines[idx].trim()
    if start_line < 0 {
      if trimmed.contains("----") && trimmed.contains("MODULE") {
        start_line = idx
      }
    } else if trimmed.has_prefix("====") {
      end_line = idx + 1
      break
    }
  }
  if start_line < 0 {
    return src
  }
  let out = StringBuilder()
  for idx = 0; idx < end_line; idx = idx + 1 {
    if idx >= start_line {
      out.write_string(lines[idx])
    }
    if idx + 1 < end_line {
      out.write_char('\n')
    }
  }
  out.to_string()
}

///|
/// Parse a TLA+ module source string into a `TlaModule` AST.
pub fn parse_module(src : String) -> TlaModule raise TlaError {
  let clean = slice_module_source(src)
  let tokens = lex_tla(clean)
  let p : Parser = { tokens, pos: 0, }

  while p.peek().kind != DashLine && p.peek().kind != Eof {
    let _ = p.advance()
  }
  p.expect_kind(DashLine, "'----'")
  p.expect_kw("MODULE")
  let name = p.expect_ident()
  p.expect_kind(DashLine, "'----'")

  let extends : Array[String] = []
  let constants : Array[String] = []
  let variables : Array[String] = []
  let assumes : Array[Expr] = []
  let defs : Array[OpDef] = []

  while p.peek().kind != Eof && p.peek().kind != EqLine {
    if p.peek().kind == DashLine {
      let _ = p.advance()
      continue
    }
    if p.is_kw("EXTENDS") {
      let _ = p.advance()
      extends.push(p.expect_ident())
      while p.peek().kind == Comma {
        let _ = p.advance()
        extends.push(p.expect_ident())
      }
      continue
    }
    if p.is_kw("CONSTANT") || p.is_kw("CONSTANTS") {
      let _ = p.advance()
      constants.push(p.expect_ident())
      while p.peek().kind == Comma {
        let _ = p.advance()
        constants.push(p.expect_ident())
      }
      continue
    }
    if p.is_kw("VARIABLE") || p.is_kw("VARIABLES") {
      let _ = p.advance()
      variables.push(p.expect_ident())
      while p.peek().kind == Comma {
        let _ = p.advance()
        variables.push(p.expect_ident())
      }
      continue
    }
    if p.is_kw("ASSUME") || p.is_kw("ASSUMPTION") {
      let _ = p.advance()
      assumes.push(p.parse_expr(0))
      continue
    }
    let mut is_local = false
    if p.is_kw("LOCAL") {
      is_local = true
      let _ = p.advance()
    }
    let def = p.parse_op_def(is_local)
    defs.push(def)
  }

  { name, extends, constants, variables, assumes, defs, }
}

///|
/// Parse a standalone TLA+ expression string (useful for tests and REPL queries).
pub fn parse_expr_str(src : String) -> Expr raise TlaError {
  let tokens = lex_tla(src)
  let p : Parser = { tokens, pos: 0, }
  let expr = p.parse_expr(0)
  if p.peek().kind != Eof {
    let tok = p.peek()
    raise ParseError(
      "unexpected trailing token \{@debug.to_string(tok.kind)} at line \{tok.line}:\{tok.col}",
    )
  }
  expr
}

///|
fn Parser::parse_op_def(self : Parser, is_local : Bool) -> OpDef raise TlaError {
  let name = self.expect_ident()
  let params : Array[String] = []
  if self.peek().kind == LParen {
    let _ = self.advance()
    if self.peek().kind != RParen {
      params.push(self.expect_ident())
      while self.peek().kind == Comma {
        let _ = self.advance()
        params.push(self.expect_ident())
      }
    }
    self.expect_kind(RParen, "')'")
  }
  self.expect_kind(DefEq, "'=='")
  let body = self.parse_expr(0)
  { name, params, body, is_local, }
}

///|
fn Parser::looks_like_op_def(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(name) => {
      if is_reserved_terminator(name) {
        return false
      }
      if self.peek_at(1).kind == DefEq {
        return true
      }
      if self.peek_at(1).kind == LParen {
        let mut off = 2
        while true {
          let t = self.peek_at(off)
          if t.kind == RParen {
            return self.peek_at(off + 1).kind == DefEq
          }
          if t.kind == Eof {
            return false
          }
          off += 1
        }
      }
      false
    }
    _ => false
  }
}

///|
fn Parser::parse_bound_pat(self : Parser) -> BoundPat raise TlaError {
  if self.peek().kind == LAngle {
    let _ = self.advance()
    let names : Array[String] = []
    names.push(self.expect_ident())
    while self.peek().kind == Comma {
      let _ = self.advance()
      names.push(self.expect_ident())
    }
    self.expect_kind(RAngle, "'>>'")
    TuplePat(names)
  } else {
    Single(self.expect_ident())
  }
}

///|
fn Parser::parse_bound_groups(
  self : Parser,
) -> Array[BoundGroup] raise TlaError {
  let groups : Array[BoundGroup] = []
  while true {
    let pats : Array[BoundPat] = []
    pats.push(self.parse_bound_pat())
    while self.peek().kind == Comma {
      let _ = self.advance()
      pats.push(self.parse_bound_pat())
    }
    self.expect_kind(In, "'\\in'")
    let domain = self.parse_expr(0)
    groups.push({ pats, domain, })
    if self.peek().kind == Comma {
      let _ = self.advance()
    } else {
      break
    }
  }
  groups
}

///|
fn Parser::parse_expr(self : Parser, min_col : Int32) -> Expr raise TlaError {
  let tok = self.peek()
  if (tok.kind == And || tok.kind == Or) && tok.col > min_col {
    let bullet_kind = tok.kind
    let bullet_col = tok.col
    let items : Array[Expr] = []
    while self.peek().kind == bullet_kind && self.peek().col == bullet_col {
      let _ = self.advance()
      items.push(self.parse_expr(bullet_col))
    }
    let lhs = if items.length() == 1 {
      items[0]
    } else if bullet_kind == And {
      ConjList(items)
    } else {
      DisjList(items)
    }
    return self.parse_infix_tail(lhs, 1, min_col)
  }
  self.parse_prec(1, min_col)
}

///|
fn binop_info(kind : TokKind) -> (BinOp, Int32, Bool)? {
  match kind {
    LeadsTo => Some((LeadsTo, 1, false))
    Implies => Some((Implies, 1, true))
    Iff => Some((Iff, 1, false))
    Or => Some((Or, 2, false))
    And => Some((And, 3, false))
    Eq => Some((Eq, 5, false))
    Neq => Some((Neq, 5, false))
    Lt => Some((Lt, 5, false))
    Le => Some((Le, 5, false))
    Gt => Some((Gt, 5, false))
    Ge => Some((Ge, 5, false))
    In => Some((In, 5, false))
    NotIn => Some((NotIn, 5, false))
    SubsetEq => Some((SubsetEq, 5, false))
    ProperSubset => Some((ProperSubset, 5, false))
    MergeFunc => Some((MergeFunc, 6, false))
    MapTo => Some((MapTo, 7, false))
    SetUnion => Some((SetUnion, 8, false))
    SetInter => Some((SetInter, 8, false))
    Backslash => Some((SetDiff, 8, false))
    Concat => Some((Concat, 9, false))
    DotDot => Some((Range, 9, false))
    Plus => Some((Add, 10, false))
    Minus => Some((Sub, 10, false))
    Star => Some((Mul, 12, false))
    IntDiv => Some((IntDiv, 12, false))
    Percent => Some((Mod, 12, false))
    Cross => Some((Cross, 12, false))
    Caret => Some((Pow, 14, true))
    _ => None
  }
}

///|
fn Parser::parse_prec(
  self : Parser,
  min_prec : Int32,
  min_col : Int32,
) -> Expr raise TlaError {
  let lhs = self.parse_prefix(min_col)
  self.parse_infix_tail(lhs, min_prec, min_col)
}

///|
fn Parser::parse_infix_tail(
  self : Parser,
  initial_lhs : Expr,
  min_prec : Int32,
  min_col : Int32,
) -> Expr raise TlaError {
  let mut lhs = initial_lhs
  while true {
    let tok = self.peek()
    if tok.col <= min_col {
      break
    }
    match binop_info(tok.kind) {
      Some((op, prec, right_assoc)) if prec >= min_prec => {
        let _ = self.advance()
        let next_min = if right_assoc { prec } else { prec + 1 }
        let rhs = self.parse_prec(next_min, min_col)
        lhs = Bin(op, lhs, rhs)
      }
      _ => break
    }
  }
  lhs
}

///|
fn Parser::parse_prefix(self : Parser, min_col : Int32) -> Expr raise TlaError {
  let tok = self.peek()
  match tok.kind {
    ForAll => {
      let _ = self.advance()
      let groups = self.parse_bound_groups()
      self.expect_kind(Colon, "':'")
      let body = self.parse_expr(min_col)
      ForAll(groups, body)
    }
    Exists => {
      let _ = self.advance()
      let groups = self.parse_bound_groups()
      self.expect_kind(Colon, "':'")
      let body = self.parse_expr(min_col)
      Exists(groups, body)
    }
    Not => {
      let _ = self.advance()
      let inner = self.parse_prec(4, min_col)
      Unary(Not, inner)
    }
    Always => {
      let _ = self.advance()
      let inner = self.parse_prec(4, min_col)
      Unary(Always, inner)
    }
    Eventually => {
      let _ = self.advance()
      let inner = self.parse_prec(4, min_col)
      Unary(Eventually, inner)
    }
    Minus => {
      let _ = self.advance()
      let inner = self.parse_prec(11, min_col)
      Unary(Neg, inner)
    }
    Ident("IF") => {
      let _ = self.advance()
      let cond = self.parse_expr(0)
      self.expect_kw("THEN")
      let then_e = self.parse_expr(0)
      self.expect_kw("ELSE")
      let else_e = self.parse_expr(min_col)
      IfThenElse(cond, then_e, else_e)
    }
    Ident("LET") => {
      let _ = self.advance()
      let local_defs : Array[OpDef] = []
      while !self.is_kw("IN") && self.peek().kind != Eof {
        if self.looks_like_op_def() {
          local_defs.push(self.parse_op_def(true))
        } else {
          let bad = self.peek()
          raise ParseError(
            "expected local definition or 'IN' inside LET at line \{bad.line}:\{bad.col}",
          )
        }
      }
      self.expect_kw("IN")
      let body = self.parse_expr(min_col)
      LetIn(local_defs, body)
    }
    Ident("CASE") => {
      let _ = self.advance()
      let arms : Array[(Expr, Expr)] = []
      let mut other_arm : Expr? = None
      let first_guard = self.parse_expr(0)
      self.expect_kind(Arrow, "'->'")
      let first_body = self.parse_expr(min_col)
      arms.push((first_guard, first_body))
      while self.peek().kind == Always && self.peek().col > min_col {
        let _ = self.advance()
        if self.is_kw("OTHER") {
          let _ = self.advance()
          self.expect_kind(Arrow, "'->'")
          other_arm = Some(self.parse_expr(min_col))
          break
        }
        let g = self.parse_expr(0)
        self.expect_kind(Arrow, "'->'")
        let b = self.parse_expr(min_col)
        arms.push((g, b))
      }
      CaseExpr(arms, other_arm)
    }
    Ident("CHOOSE") => {
      let _ = self.advance()
      let pat = self.parse_bound_pat()
      self.expect_kind(In, "'\\in'")
      let domain = self.parse_expr(0)
      self.expect_kind(Colon, "':'")
      let pred = self.parse_expr(min_col)
      Choose(pat, domain, pred)
    }
    Ident("UNCHANGED") => {
      let _ = self.advance()
      let target = self.parse_prec(13, min_col)
      Unary(Unchanged, target)
    }
    Ident("ENABLED") => {
      let _ = self.advance()
      let target = self.parse_prec(13, min_col)
      Unary(Enabled, target)
    }
    Ident("SUBSET") => {
      let _ = self.advance()
      let target = self.parse_prec(13, min_col)
      Unary(Subset, target)
    }
    Ident("UNION") => {
      let _ = self.advance()
      let target = self.parse_prec(13, min_col)
      Unary(Union, target)
    }
    Ident("DOMAIN") => {
      let _ = self.advance()
      let target = self.parse_prec(13, min_col)
      Unary(Domain, target)
    }
    _ => self.parse_postfix()
  }
}

///|
fn Parser::parse_postfix(self : Parser) -> Expr raise TlaError {
  let mut expr = self.parse_atom()
  while true {
    match self.peek().kind {
      Prime => {
        let _ = self.advance()
        expr = Unary(Prime, expr)
      }
      Dot => {
        let _ = self.advance()
        let field = self.expect_ident()
        expr = RecordField(expr, field)
      }
      LBracket => {
        let _ = self.advance()
        let args : Array[Expr] = []
        args.push(self.parse_expr(0))
        while self.peek().kind == Comma {
          let _ = self.advance()
          args.push(self.parse_expr(0))
        }
        self.expect_kind(RBracket, "']'")
        expr = FuncApply(expr, args)
      }
      _ => break
    }
  }
  expr
}

///|
fn Parser::parse_atom(self : Parser) -> Expr raise TlaError {
  let tok = self.peek()
  match tok.kind {
    Int(v) => {
      let _ = self.advance()
      IntLit(v)
    }
    Str(s) => {
      let _ = self.advance()
      StrLit(s)
    }
    At => {
      let _ = self.advance()
      At
    }
    LParen => {
      let _ = self.advance()
      let inner = self.parse_expr(0)
      self.expect_kind(RParen, "')'")
      inner
    }
    LAngle => {
      let _ = self.advance()
      let items : Array[Expr] = []
      if self.peek().kind != RAngle {
        items.push(self.parse_expr(0))
        while self.peek().kind == Comma {
          let _ = self.advance()
          items.push(self.parse_expr(0))
        }
      }
      self.expect_kind(RAngle, "'>>'")
      TupleLit(items)
    }
    LBrace => self.parse_brace()
    LBracket => self.parse_bracket()
    Ident(name) => {
      if is_reserved_terminator(name) {
        raise ParseError(
          "unexpected keyword '\{name}' at line \{tok.line}:\{tok.col}",
        )
      }
      if name == "TRUE" {
        let _ = self.advance()
        return BoolLit(true)
      }
      if name == "FALSE" {
        let _ = self.advance()
        return BoolLit(false)
      }
      if name == "BOOLEAN" || name == "STRING" || name == "Nat" || name == "Int" {
        let _ = self.advance()
        return BuiltinSet(name)
      }
      if (name == "WF_" || name == "SF_") && self.peek_at(1).kind == LAngle {
        let _ = self.advance()
        let kind : FairnessKind = if name == "WF_" { Weak } else { Strong }
        let vars_expr = self.parse_atom()
        self.expect_kind(LParen, "'('")
        let action = self.parse_expr(0)
        self.expect_kind(RParen, "')'")
        return Fairness(kind, vars_expr, action)
      }
      if (name.has_prefix("WF_") || name.has_prefix("SF_")) &&
        name.length() > 3 &&
        self.peek_at(1).kind == LParen {
        let _ = self.advance()
        let kind : FairnessKind = if name.has_prefix("WF_") {
          Weak
        } else {
          Strong
        }
        let vars_name = name[3:].to_owned()
        self.expect_kind(LParen, "'('")
        let action = self.parse_expr(0)
        self.expect_kind(RParen, "')'")
        return Fairness(kind, Ident(vars_name), action)
      }
      let _ = self.advance()
      if self.peek().kind == LParen {
        let _ = self.advance()
        let args : Array[Expr] = []
        if self.peek().kind != RParen {
          args.push(self.parse_expr(0))
          while self.peek().kind == Comma {
            let _ = self.advance()
            args.push(self.parse_expr(0))
          }
        }
        self.expect_kind(RParen, "')'")
        Call(name, args)
      } else {
        Ident(name)
      }
    }
    _ =>
      raise ParseError(
        "unexpected token \{@debug.to_string(tok.kind)} at line \{tok.line}:\{tok.col}",
      )
  }
}

///|
fn Parser::parse_brace(self : Parser) -> Expr raise TlaError {
  self.expect_kind(LBrace, "'{'")
  if self.peek().kind == RBrace {
    let _ = self.advance()
    return SetEnum([])
  }
  let saved = self.pos
  let filter_opt : Expr? = try {
    let pat = self.parse_bound_pat()
    if self.peek().kind == In {
      let _ = self.advance()
      let domain = self.parse_expr(0)
      if self.peek().kind == Colon {
        let _ = self.advance()
        let pred = self.parse_expr(0)
        self.expect_kind(RBrace, "'}'")
        Some(SetFilter(pat, domain, pred))
      } else {
        None
      }
    } else {
      None
    }
  } catch {
    _ => None
  }
  match filter_opt {
    Some(e) => return e
    None => self.pos = saved
  }

  let first = self.parse_expr(0)
  if self.peek().kind == Colon {
    let _ = self.advance()
    let groups = self.parse_bound_groups()
    self.expect_kind(RBrace, "'}'")
    return SetMap(first, groups)
  }

  let items : Array[Expr] = [first]
  while self.peek().kind == Comma {
    let _ = self.advance()
    items.push(self.parse_expr(0))
  }
  self.expect_kind(RBrace, "'}'")
  SetEnum(items)
}

///|
fn Parser::parse_bracket(self : Parser) -> Expr raise TlaError {
  self.expect_kind(LBracket, "'['")
  match (self.peek().kind, self.peek_at(1).kind) {
    (Ident(_), MapsTo) => {
      let fields : Array[(String, Expr)] = []
      while true {
        let fname = self.expect_ident()
        self.expect_kind(MapsTo, "'|->'")
        let val = self.parse_expr(0)
        fields.push((fname, val))
        if self.peek().kind == Comma {
          let _ = self.advance()
        } else {
          break
        }
      }
      self.expect_kind(RBracket, "']'")
      return RecordLit(fields)
    }
    (Ident(_), Colon) => {
      let fields : Array[(String, Expr)] = []
      while true {
        let fname = self.expect_ident()
        self.expect_kind(Colon, "':'")
        let dom = self.parse_expr(0)
        fields.push((fname, dom))
        if self.peek().kind == Comma {
          let _ = self.advance()
        } else {
          break
        }
      }
      self.expect_kind(RBracket, "']'")
      return RecordSet(fields)
    }
    _ => ()
  }

  let saved = self.pos
  let func_opt : Expr? = try {
    let groups = self.parse_bound_groups()
    if self.peek().kind == MapsTo {
      let _ = self.advance()
      let body = self.parse_expr(0)
      self.expect_kind(RBracket, "']'")
      Some(FuncDef(groups, body))
    } else {
      None
    }
  } catch {
    _ => None
  }
  match func_opt {
    Some(e) => return e
    None => self.pos = saved
  }

  let first = self.parse_expr(0)
  if self.is_kw("EXCEPT") {
    let _ = self.advance()
    let clauses : Array[ExceptClause] = []
    while true {
      self.expect_kind(Bang, "'!'")
      let path : Array[ExceptStep] = []
      while true {
        if self.peek().kind == LBracket {
          let _ = self.advance()
          let idxs : Array[Expr] = []
          idxs.push(self.parse_expr(0))
          while self.peek().kind == Comma {
            let _ = self.advance()
            idxs.push(self.parse_expr(0))
          }
          self.expect_kind(RBracket, "']'")
          path.push(Index(idxs))
        } else if self.peek().kind == Dot {
          let _ = self.advance()
          path.push(Field(self.expect_ident()))
        } else {
          break
        }
      }
      if path.is_empty() {
        let tok = self.peek()
        raise ParseError(
          "EXCEPT clause requires at least one ![idx] or !.field step at line \{tok.line}:\{tok.col}",
        )
      }
      self.expect_kind(Eq, "'='")
      let val = self.parse_expr(0)
      clauses.push({ path, value: val, })
      if self.peek().kind == Comma {
        let _ = self.advance()
      } else {
        break
      }
    }
    self.expect_kind(RBracket, "']'")
    return Except(first, clauses)
  }

  if self.peek().kind == Arrow {
    let _ = self.advance()
    let codomain = self.parse_expr(0)
    self.expect_kind(RBracket, "']'")
    return FuncSet(first, codomain)
  }

  self.expect_kind(RBracket, "']'")
  match self.peek().kind {
    Ident(s) if s.has_prefix("_") => {
      let _ = self.advance()
      if s == "_" {
        let vars_expr = self.parse_atom()
        StutterAction(first, vars_expr)
      } else {
        StutterAction(first, Ident(s[1:].to_owned()))
      }
    }
    _ => {
      let tok = self.peek()
      raise ParseError(
        "expected subscript '_vars' after '[action]' at line \{tok.line}:\{tok.col}",
      )
    }
  }
}
