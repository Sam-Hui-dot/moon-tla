///|
/// Errors raised during TLA+ lexing, parsing, configuration loading, evaluation, or model checking.
#derive(Debug, Eq)
pub(all) suberror TlaError {
  LexError(String)
  ParseError(String)
  CfgError(String)
  EvalError(String)
  CheckError(String)
  InvalidInput(String)
}

///|
pub extend TlaError with @debug.Debug::{to_repr}

///|
pub extend TlaError with Eq::{not_equal, equal}

///|
/// Return a concise human-readable diagnostic message for any error.
pub fn error_message(error : Error) -> String {
  match error {
    LexError(msg)
    | ParseError(msg)
    | CfgError(msg)
    | EvalError(msg)
    | CheckError(msg)
    | InvalidInput(msg) => msg
    other => other.to_string()
  }
}

///|
/// Bound pattern for quantifiers, set comprehensions, and function constructors.
#derive(Debug, Eq)
pub(all) enum BoundPat {
  Single(String)
  TuplePat(Array[String])
}

///|
pub extend BoundPat with @debug.Debug::{to_repr}

///|
pub extend BoundPat with Eq::{not_equal, equal}

///|
/// One or more bound patterns sharing a common domain expression (`x, y \in S`).
#derive(Debug, Eq)
pub(all) struct BoundGroup {
  pats : Array[BoundPat]
  domain : Expr
}

///|
pub extend BoundGroup with @debug.Debug::{to_repr}

///|
pub extend BoundGroup with Eq::{not_equal, equal}

///|
/// Path component in `[f EXCEPT ![k] = v, !.field = v2]`.
#derive(Debug, Eq)
pub(all) enum ExceptStep {
  Index(Array[Expr])
  Field(String)
}

///|
pub extend ExceptStep with @debug.Debug::{to_repr}

///|
pub extend ExceptStep with Eq::{not_equal, equal}

///|
/// Single update clause inside an `EXCEPT` expression.
#derive(Debug, Eq)
pub(all) struct ExceptClause {
  path : Array[ExceptStep]
  value : Expr
}

///|
pub extend ExceptClause with @debug.Debug::{to_repr}

///|
pub extend ExceptClause with Eq::{not_equal, equal}

///|
/// Unary operators in TLA+.
#derive(Debug, Eq)
pub(all) enum UnaryOp {
  Not
  Neg
  Subset
  Union
  Domain
  Prime
  Unchanged
  Enabled
  Always
  Eventually
}

///|
pub extend UnaryOp with @debug.Debug::{to_repr}

///|
pub extend UnaryOp with Eq::{not_equal, equal}

///|
/// Binary operators in TLA+.
#derive(Debug, Eq)
pub(all) enum BinOp {
  And
  Or
  Implies
  Iff
  LeadsTo
  Eq
  Neq
  Lt
  Le
  Gt
  Ge
  In
  NotIn
  SubsetEq
  ProperSubset
  SetUnion
  SetInter
  SetDiff
  Range
  Concat
  Add
  Sub
  Mul
  IntDiv
  Mod
  Pow
  Cross
  MapTo
  MergeFunc
}

///|
pub extend BinOp with @debug.Debug::{to_repr}

///|
pub extend BinOp with Eq::{not_equal, equal}

///|
/// Fairness kind (`WF_v(A)` or `SF_v(A)`).
#derive(Debug, Eq)
pub(all) enum FairnessKind {
  Weak
  Strong
}

///|
pub extend FairnessKind with @debug.Debug::{to_repr}

///|
pub extend FairnessKind with Eq::{not_equal, equal}

///|
/// Operator definition (`Op(a, b) == body`).
#derive(Debug, Eq)
pub(all) struct OpDef {
  name : String
  params : Array[String]
  body : Expr
  is_local : Bool
}

///|
pub extend OpDef with @debug.Debug::{to_repr}

///|
pub extend OpDef with Eq::{not_equal, equal}

///|
/// Core TLA+ expression / action / temporal formula AST.
#derive(Debug, Eq)
pub(all) enum Expr {
  BoolLit(Bool)
  IntLit(Int64)
  StrLit(String)
  BuiltinSet(String)
  Ident(String)
  At
  Call(String, Array[Expr])
  Unary(UnaryOp, Expr)
  Bin(BinOp, Expr, Expr)
  ConjList(Array[Expr])
  DisjList(Array[Expr])
  IfThenElse(Expr, Expr, Expr)
  CaseExpr(Array[(Expr, Expr)], Expr?)
  LetIn(Array[OpDef], Expr)
  ForAll(Array[BoundGroup], Expr)
  Exists(Array[BoundGroup], Expr)
  Choose(BoundPat, Expr, Expr)
  SetEnum(Array[Expr])
  SetFilter(BoundPat, Expr, Expr)
  SetMap(Expr, Array[BoundGroup])
  TupleLit(Array[Expr])
  RecordLit(Array[(String, Expr)])
  RecordSet(Array[(String, Expr)])
  FuncDef(Array[BoundGroup], Expr)
  FuncSet(Expr, Expr)
  FuncApply(Expr, Array[Expr])
  RecordField(Expr, String)
  Except(Expr, Array[ExceptClause])
  StutterAction(Expr, Expr)
  Fairness(FairnessKind, Expr, Expr)
}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend Expr with Eq::{not_equal, equal}

///|
/// Parsed TLA+ module.
#derive(Debug, Eq)
pub(all) struct TlaModule {
  name : String
  extends : Array[String]
  constants : Array[String]
  variables : Array[String]
  assumes : Array[Expr]
  defs : Array[OpDef]
}

///|
pub extend TlaModule with @debug.Debug::{to_repr}

///|
pub extend TlaModule with Eq::{not_equal, equal}

///|
/// Look up an operator definition by name inside a parsed TLA+ module.
pub fn TlaModule::find_def(self : TlaModule, name : String) -> OpDef? {
  for d in self.defs {
    if d.name == name {
      return Some(d)
    }
  }
  None
}

///|
/// Parsed constant literal value from a TLC `.cfg` file.
#derive(Debug, Eq)
pub(all) enum CfgValue {
  CfgInt(Int64)
  CfgBool(Bool)
  CfgStr(String)
  CfgModel(String)
  CfgSet(Array[CfgValue])
}

///|
pub extend CfgValue with @debug.Debug::{to_repr}

///|
pub extend CfgValue with Eq::{not_equal, equal}

///|
/// Parsed TLC `.cfg` configuration file.
#derive(Debug, Eq)
pub(all) struct TlaConfig {
  specification : String?
  init : String?
  next : String?
  invariants : Array[String]
  properties : Array[String]
  constants : Array[(String, CfgValue)]
  overrides : Array[(String, String)]
  symmetry : String?
  check_deadlock : Bool
}

///|
pub extend TlaConfig with @debug.Debug::{to_repr}

///|
pub extend TlaConfig with Eq::{not_equal, equal}
