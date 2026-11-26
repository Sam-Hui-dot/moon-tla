///|
#derive(Debug, Eq)
priv enum TokKind {
  Ident(String)
  Int(Int64)
  Str(String)
  DashLine
  EqLine
  DefEq // ==
  And // /\ or \land
  Or // \/ or \lor
  Not // ~ or \lnot or \neg
  Implies // =>
  Iff // <=>
  LeadsTo // ~>
  Always // []
  Eventually // <>
  Eq // =
  Neq // # or /= or \neq
  Lt // <
  Le // <= or =< or \leq
  Gt // >
  Ge // >= or \geq
  In // \in
  NotIn // \notin
  SubsetEq // \subseteq
  ProperSubset // \subset
  SetUnion // \cup or \union
  SetInter // \cap or \intersect
  Backslash // \
  ForAll // \A or \AA
  Exists // \E or \EE
  IntDiv // \div
  Concat // \o or \circ
  Cross // \X or \times
  MapTo // :>
  MergeFunc // @@
  MapsTo // |->
  Arrow // ->
  DotDot // ..
  Dot // .
  Comma // ,
  Colon // :
  Bang // !
  At // @
  Prime // '
  Plus // +
  Minus // -
  Star // *
  Percent // %
  Caret // ^
  LParen // (
  RParen // )
  LBracket // [
  RBracket // ]
  LBrace // {
  RBrace // }
  LAngle // <<
  RAngle // >>
  Eof
}

///|
priv struct Token {
  kind : TokKind
  line : Int32
  col : Int32
}

///|
fn is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

///|
fn is_ident_cont(ch : Char) -> Bool {
  is_ident_start(ch) || (ch >= '0' && ch <= '9')
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn lex_tla(src : String) -> Array[Token] raise TlaError {
  let chars = src.to_array()
  let n = chars.length()
  let tokens : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut col = 1

  fn peek(offset : Int32) -> Char? {
    let idx = i + offset
    if idx >= 0 && idx < n {
      Some(chars[idx])
    } else {
      None
    }
  }

  fn advance() -> Char {
    let c = chars[i]
    i += 1
    if c == '\n' {
      line += 1
      col = 1
    } else {
      col += 1
    }
    c
  }

  while i < n {
    let c = chars[i]
    // Skip whitespace
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      let _ = advance()
      continue
    }
    // Line comment: \*
    if c == '\\' && peek(1) == Some('*') {
      let _ = advance()
      let _ = advance()
      while i < n && chars[i] != '\n' {
        let _ = advance()
      }
      continue
    }
    // Nested block comment: (* ... *)
    if c == '(' && peek(1) == Some('*') {
      let start_line = line
      let _ = advance()
      let _ = advance()
      let mut depth = 1
      while i < n && depth > 0 {
        if chars[i] == '(' && peek(1) == Some('*') {
          let _ = advance()
          let _ = advance()
          depth += 1
        } else if chars[i] == '*' && peek(1) == Some(')') {
          let _ = advance()
          let _ = advance()
          depth -= 1
        } else {
          let _ = advance()
        }
      }
      if depth != 0 {
        raise LexError(
          "unterminated block comment starting at line \{start_line}",
        )
      }
      continue
    }

    let tok_line = line
    let tok_col = col

    // String literal
    if c == '"' {
      let _ = advance()
      let sb = StringBuilder()
      let mut closed = false
      while i < n {
        let ch = advance()
        if ch == '"' {
          closed = true
          break
        }
        if ch == '\\' && i < n {
          let esc = advance()
          match esc {
            'n' => sb.write_char('\n')
            't' => sb.write_char('\t')
            'r' => sb.write_char('\r')
            '"' => sb.write_char('"')
            '\\' => sb.write_char('\\')
            other => sb.write_char(other)
          }
        } else {
          sb.write_char(ch)
        }
      }
      if !closed {
        raise LexError(
          "unterminated string literal at line \{tok_line}:\{tok_col}",
        )
      }
      tokens.push({ kind: Str(sb.to_string()), line: tok_line, col: tok_col, })
      continue
    }

    // Integer literal
    if is_digit(c) {
      let sb = StringBuilder()
      while i < n && is_digit(chars[i]) {
        sb.write_char(advance())
      }
      let raw = sb.to_string()
      let val = @string.parse_int64(raw) catch {
        _ =>
          raise LexError(
            "invalid integer literal '\{raw}' at line \{tok_line}:\{tok_col}",
          )
      }
      tokens.push({ kind: Int(val), line: tok_line, col: tok_col, })
      continue
    }

    // Identifier or keyword
    if is_ident_start(c) {
      let sb = StringBuilder()
      while i < n && is_ident_cont(chars[i]) {
        sb.write_char(advance())
      }
      tokens.push({ kind: Ident(sb.to_string()), line: tok_line, col: tok_col, })
      continue
    }

    // Backslash operators & \/
    if c == '\\' {
      let _ = advance()
      if i < n && chars[i] == '/' {
        let _ = advance()
        tokens.push({ kind: Or, line: tok_line, col: tok_col, })
        continue
      }
      if i < n && is_ident_start(chars[i]) {
        let sb = StringBuilder()
        while i < n && is_ident_cont(chars[i]) {
          sb.write_char(advance())
        }
        let word = sb.to_string()
        let kind : TokKind = match word {
          "in" => In
          "notin" => NotIn
          "subseteq" => SubsetEq
          "subset" => ProperSubset
          "cup" | "union" => SetUnion
          "cap" | "intersect" => SetInter
          "A" | "AA" => ForAll
          "E" | "EE" => Exists
          "lnot" | "neg" => Not
          "land" => And
          "lor" => Or
          "div" => IntDiv
          "o" | "circ" => Concat
          "X" | "times" => Cross
          "leq" => Le
          "geq" => Ge
          "neq" => Neq
          _ =>
            raise LexError(
              "unknown backslash operator '\\\{word}' at line \{tok_line}:\{tok_col}",
            )
        }
        tokens.push({ kind, line: tok_line, col: tok_col, })
        continue
      }
      tokens.push({ kind: Backslash, line: tok_line, col: tok_col, })
      continue
    }

    // Dash line (----) or -> or -
    if c == '-' {
      if peek(1) == Some('-') && peek(2) == Some('-') && peek(3) == Some('-') {
        while i < n && chars[i] == '-' {
          let _ = advance()
        }
        tokens.push({ kind: DashLine, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Arrow, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Minus, line: tok_line, col: tok_col, })
      continue
    }

    // Equals line (====), ==, =>, =<, =
    if c == '=' {
      if peek(1) == Some('=') && peek(2) == Some('=') && peek(3) == Some('=') {
        while i < n && chars[i] == '=' {
          let _ = advance()
        }
        tokens.push({ kind: EqLine, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('=') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: DefEq, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Implies, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('<') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Le, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Eq, line: tok_line, col: tok_col, })
      continue
    }

    // Slash: /\ or /=
    if c == '/' {
      if peek(1) == Some('\\') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: And, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('=') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Neq, line: tok_line, col: tok_col, })
        continue
      }
      raise LexError("unexpected '/' at line \{tok_line}:\{tok_col}")
    }

    // < : <=>, <<, <>, <=, <
    if c == '<' {
      if peek(1) == Some('=') && peek(2) == Some('>') {
        let _ = advance()
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Iff, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('<') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: LAngle, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Eventually, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('=') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Le, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Lt, line: tok_line, col: tok_col, })
      continue
    }

    // > : >>, >=, >
    if c == '>' {
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: RAngle, line: tok_line, col: tok_col, })
        continue
      }
      if peek(1) == Some('=') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Ge, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Gt, line: tok_line, col: tok_col, })
      continue
    }

    // [ : [] or [
    if c == '[' {
      if peek(1) == Some(']') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: Always, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: LBracket, line: tok_line, col: tok_col, })
      continue
    }

    // ~ : ~> or ~
    if c == '~' {
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: LeadsTo, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Not, line: tok_line, col: tok_col, })
      continue
    }

    // |->
    if c == '|' && peek(1) == Some('-') && peek(2) == Some('>') {
      let _ = advance()
      let _ = advance()
      let _ = advance()
      tokens.push({ kind: MapsTo, line: tok_line, col: tok_col, })
      continue
    }

    // :> or :
    if c == ':' {
      if peek(1) == Some('>') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: MapTo, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Colon, line: tok_line, col: tok_col, })
      continue
    }

    // @@ or @
    if c == '@' {
      if peek(1) == Some('@') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: MergeFunc, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: At, line: tok_line, col: tok_col, })
      continue
    }

    // .. or .
    if c == '.' {
      if peek(1) == Some('.') {
        let _ = advance()
        let _ = advance()
        tokens.push({ kind: DotDot, line: tok_line, col: tok_col, })
        continue
      }
      let _ = advance()
      tokens.push({ kind: Dot, line: tok_line, col: tok_col, })
      continue
    }

    // Single-character tokens
    let single : TokKind? = match c {
      '#' => Some(Neq)
      ',' => Some(Comma)
      '!' => Some(Bang)
      '\'' => Some(Prime)
      '+' => Some(Plus)
      '*' => Some(Star)
      '%' => Some(Percent)
      '^' => Some(Caret)
      '(' => Some(LParen)
      ')' => Some(RParen)
      ']' => Some(RBracket)
      '{' => Some(LBrace)
      '}' => Some(RBrace)
      _ => None
    }
    match single {
      Some(k) => {
        let _ = advance()
        tokens.push({ kind: k, line: tok_line, col: tok_col, })
      }
      None =>
        raise LexError(
          "unexpected character '\{c}' at line \{tok_line}:\{tok_col}",
        )
    }
  }

  tokens.push({ kind: Eof, line, col, })
  tokens
}
