///|
/// Canonical TLA+ runtime value with total ordering and unique normal form.
/// - `Set` elements are strictly sorted and deduplicated.
/// - `Tuple` represents sequences and 1..n-indexed functions (including empty `<<>>`).
/// - `Func` represents general functions and records (with sorted unique keys);
///   any function whose domain is exact `1..n` is normalized to `Tuple`.
#derive(Debug)
pub(all) enum TlaVal {
  Bool(Bool)
  Int(Int64)
  Str(String)
  ModelVal(String)
  Set(Array[TlaVal])
  Tuple(Array[TlaVal])
  Func(Array[(TlaVal, TlaVal)])
}

///|
pub extend TlaVal with @debug.Debug::{to_repr}

///|
fn val_tag(v : TlaVal) -> Int32 {
  match v {
    Bool(_) => 0
    Int(_) => 1
    Str(_) => 2
    ModelVal(_) => 3
    Set(_) => 4
    Tuple(_) => 5
    Func(_) => 6
  }
}

///|
/// Deterministic total order over all canonical `TlaVal` values.
pub fn compare_val(a : TlaVal, b : TlaVal) -> Int32 {
  let ta = val_tag(a)
  let tb = val_tag(b)
  if ta != tb {
    return if ta < tb { -1 } else { 1 }
  }
  match (a, b) {
    (Bool(x), Bool(y)) => if x == y { 0 } else if !x { -1 } else { 1 }
    (Int(x), Int(y)) => if x < y { -1 } else if x > y { 1 } else { 0 }
    (Str(x), Str(y)) => x.compare(y)
    (ModelVal(x), ModelVal(y)) => x.compare(y)
    (Set(xs), Set(ys)) | (Tuple(xs), Tuple(ys)) => {
      let lx = xs.length()
      let ly = ys.length()
      let lim = if lx < ly { lx } else { ly }
      for i = 0; i < lim; i = i + 1 {
        let c = compare_val(xs[i], ys[i])
        if c != 0 {
          return c
        }
      }
      if lx < ly {
        -1
      } else if lx > ly {
        1
      } else {
        0
      }
    }
    (Func(xs), Func(ys)) => {
      let lx = xs.length()
      let ly = ys.length()
      let lim = if lx < ly { lx } else { ly }
      for i = 0; i < lim; i = i + 1 {
        let ck = compare_val(xs[i].0, ys[i].0)
        if ck != 0 {
          return ck
        }
        let cv = compare_val(xs[i].1, ys[i].1)
        if cv != 0 {
          return cv
        }
      }
      if lx < ly {
        -1
      } else if lx > ly {
        1
      } else {
        0
      }
    }
    _ => 0
  }
}

///|
pub impl Eq for TlaVal with fn equal(self, other) {
  compare_val(self, other) == 0
}

///|
pub extend TlaVal with Eq::{not_equal, equal}

///|
pub impl Compare for TlaVal with fn compare(self, other) {
  compare_val(self, other)
}

///|
pub extend TlaVal with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
/// Build a canonical sorted, deduplicated TLA+ set.
pub fn make_set(items : Array[TlaVal]) -> TlaVal {
  if items.is_empty() {
    return Set([])
  }
  let sorted = items.copy()
  sorted.sort_by(compare_val)
  let dedup : Array[TlaVal] = [sorted[0]]
  for i = 1; i < sorted.length(); i = i + 1 {
    if compare_val(sorted[i], dedup[dedup.length() - 1]) != 0 {
      dedup.push(sorted[i])
    }
  }
  Set(dedup)
}

///|
/// Build a canonical TLA+ function; functions with domain `1..n` (including empty)
/// are normalized to `Tuple` to match TLA+ function/sequence identity.
pub fn make_func(entries : Array[(TlaVal, TlaVal)]) -> TlaVal {
  if entries.is_empty() {
    return Tuple([])
  }
  let sorted = entries.copy()
  sorted.sort_by(fn(a, b) { compare_val(a.0, b.0) })
  // Deduplicate keeping first occurrence (callers ensure unique keys)
  let uniq : Array[(TlaVal, TlaVal)] = [sorted[0]]
  for i = 1; i < sorted.length(); i = i + 1 {
    if compare_val(sorted[i].0, uniq[uniq.length() - 1].0) != 0 {
      uniq.push(sorted[i])
    }
  }
  let mut is_seq = true
  for i = 0; i < uniq.length(); i = i + 1 {
    match uniq[i].0 {
      Int(k) if k == (i + 1).to_int64() => ()
      _ => {
        is_seq = false
        break
      }
    }
  }
  if is_seq {
    let vals : Array[TlaVal] = []
    for pair in uniq {
      vals.push(pair.1)
    }
    Tuple(vals)
  } else {
    Func(uniq)
  }
}

///|
/// Binary search for `target` in a canonical sorted array of `TlaVal`.
pub fn set_contains(elems : Array[TlaVal], target : TlaVal) -> Bool {
  let mut lo = 0
  let mut hi = elems.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let c = compare_val(elems[mid], target)
    if c == 0 {
      return true
    } else if c < 0 {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  false
}

///|
/// Look up a key in a `Tuple` or `Func`.
pub fn func_lookup(f : TlaVal, key : TlaVal) -> TlaVal? {
  match f {
    Tuple(items) =>
      match key {
        Int(idx) => {
          let i = idx.to_int() - 1
          if i >= 0 && i < items.length() {
            Some(items[i])
          } else {
            None
          }
        }
        _ => None
      }
    Func(entries) => {
      let mut lo = 0
      let mut hi = entries.length() - 1
      while lo <= hi {
        let mid = lo + (hi - lo) / 2
        let c = compare_val(entries[mid].0, key)
        if c == 0 {
          return Some(entries[mid].1)
        } else if c < 0 {
          lo = mid + 1
        } else {
          hi = mid - 1
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Return the canonical `DOMAIN` set of a `Tuple` or `Func`.
pub fn func_domain(f : TlaVal) -> TlaVal raise TlaError {
  match f {
    Tuple(items) => {
      let keys : Array[TlaVal] = []
      for i = 0; i < items.length(); i = i + 1 {
        keys.push(Int((i + 1).to_int64()))
      }
      Set(keys)
    }
    Func(entries) => {
      let keys : Array[TlaVal] = []
      for pair in entries {
        keys.push(pair.0)
      }
      Set(keys)
    }
    _ => raise EvalError("DOMAIN requires a function, record, or tuple")
  }
}

///|
fn is_plain_ident_str(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let mut first = true
  for ch in s {
    if first {
      if !is_ident_start(ch) {
        return false
      }
      first = false
    } else if !is_ident_cont(ch) {
      return false
    }
  }
  true
}

///|
fn write_tla_val(v : TlaVal, sb : StringBuilder) -> Unit {
  match v {
    Bool(true) => sb.write_string("TRUE")
    Bool(false) => sb.write_string("FALSE")
    Int(n) => sb.write_string(n.to_string())
    Str(s) => {
      sb.write_char('"')
      for ch in s {
        match ch {
          '"' => sb.write_string("\\\"")
          '\\' => sb.write_string("\\\\")
          '\n' => sb.write_string("\\n")
          _ => sb.write_char(ch)
        }
      }
      sb.write_char('"')
    }
    ModelVal(name) => sb.write_string(name)
    Set(items) => {
      sb.write_char('{')
      for i = 0; i < items.length(); i = i + 1 {
        if i > 0 {
          sb.write_string(", ")
        }
        write_tla_val(items[i], sb)
      }
      sb.write_char('}')
    }
    Tuple(items) => {
      sb.write_string("<<")
      for i = 0; i < items.length(); i = i + 1 {
        if i > 0 {
          sb.write_string(", ")
        }
        write_tla_val(items[i], sb)
      }
      sb.write_string(">>")
    }
    Func(entries) => {
      let mut all_rec_fields = !entries.is_empty()
      for pair in entries {
        match pair.0 {
          Str(k) if is_plain_ident_str(k) => ()
          _ => {
            all_rec_fields = false
            break
          }
        }
      }
      if all_rec_fields {
        sb.write_char('[')
        for i = 0; i < entries.length(); i = i + 1 {
          if i > 0 {
            sb.write_string(", ")
          }
          match entries[i].0 {
            Str(k) => sb.write_string(k)
            _ => ()
          }
          sb.write_string(" |-> ")
          write_tla_val(entries[i].1, sb)
        }
        sb.write_char(']')
      } else {
        sb.write_char('(')
        for i = 0; i < entries.length(); i = i + 1 {
          if i > 0 {
            sb.write_string(" @@ ")
          }
          write_tla_val(entries[i].0, sb)
          sb.write_string(" :> ")
          write_tla_val(entries[i].1, sb)
        }
        sb.write_char(')')
      }
    }
  }
}

///|
/// Format any `TlaVal` into canonical human-readable TLA+ notation.
pub fn format_val(v : TlaVal) -> String {
  let sb = StringBuilder()
  write_tla_val(v, sb)
  sb.to_string()
}

///|
/// 128-bit canonical state/value fingerprint (`(UInt64, UInt64)`).
priv struct Hasher128 {
  mut h1 : UInt64
  mut h2 : UInt64
}

///|
fn Hasher128::new() -> Hasher128 {
  { h1: 0xcbf29ce484222325UL, h2: 0x9e3779b97f4a7c15UL, }
}

///|
fn Hasher128::mix_u64(self : Hasher128, x : UInt64) -> Unit {
  let a = (self.h1 ^ x) * 0x100000001b3UL
  self.h1 = a ^ (a >> 31)
  let b = (self.h2 ^ (x + 0x9e3779b97f4a7c15UL)) * 0xbf58476d1ce4e5b9UL
  self.h2 = b ^ (b >> 27)
}

///|
fn Hasher128::mix_str(self : Hasher128, s : String) -> Unit {
  self.mix_u64(s.length().to_uint64())
  for ch in s {
    self.mix_u64(ch.to_int().to_uint64())
  }
}

///|
fn Hasher128::mix_val(self : Hasher128, v : TlaVal) -> Unit {
  match v {
    Bool(b) => {
      self.mix_u64(1UL)
      self.mix_u64(if b { 1UL } else { 0UL })
    }
    Int(n) => {
      self.mix_u64(2UL)
      self.mix_u64(n.reinterpret_as_uint64())
    }
    Str(s) => {
      self.mix_u64(3UL)
      self.mix_str(s)
    }
    ModelVal(s) => {
      self.mix_u64(4UL)
      self.mix_str(s)
    }
    Set(items) => {
      self.mix_u64(5UL)
      self.mix_u64(items.length().to_uint64())
      for item in items {
        self.mix_val(item)
      }
    }
    Tuple(items) => {
      self.mix_u64(6UL)
      self.mix_u64(items.length().to_uint64())
      for item in items {
        self.mix_val(item)
      }
    }
    Func(entries) => {
      self.mix_u64(7UL)
      self.mix_u64(entries.length().to_uint64())
      for pair in entries {
        self.mix_val(pair.0)
        self.mix_val(pair.1)
      }
    }
  }
}

///|
/// Compute a deterministic 128-bit canonical fingerprint of a `TlaVal`.
pub fn fingerprint_val(v : TlaVal) -> (UInt64, UInt64) {
  let h = Hasher128::new()
  h.mix_val(v)
  (h.h1, h.h2)
}

///|
/// Compute a deterministic 128-bit canonical fingerprint of a state vector.
pub fn fingerprint_state(
  var_names : Array[String],
  values : Array[TlaVal],
) -> (UInt64, UInt64) {
  let h = Hasher128::new()
  h.mix_u64(values.length().to_uint64())
  for i = 0; i < values.length(); i = i + 1 {
    if i < var_names.length() {
      h.mix_str(var_names[i])
    }
    h.mix_val(values[i])
  }
  (h.h1, h.h2)
}

///|
/// Convert a `.cfg` literal value into a canonical `TlaVal`.
pub fn cfg_value_to_val(v : CfgValue) -> TlaVal {
  match v {
    CfgInt(n) => Int(n)
    CfgBool(b) => Bool(b)
    CfgStr(s) => Str(s)
    CfgModel(m) => ModelVal(m)
    CfgSet(items) => {
      let vals : Array[TlaVal] = []
      for item in items {
        vals.push(cfg_value_to_val(item))
      }
      make_set(vals)
    }
  }
}
