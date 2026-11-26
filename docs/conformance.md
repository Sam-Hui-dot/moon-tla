# `moon-tla@0.2.0` 与官方 Java TLC `v1.7.4` 语义对齐矩阵

本文档诚实记录 `moon-tla@0.2.0` 对 TLA+ 语言子集、TLC `.cfg` 配置、对称性约简与时序活性检测的覆盖范围及尚未支持的边界。

## 1. 已对齐并通过 Java TLC `v1.7.4` 对拍的能力

| 类别 | 支持特性 | 说明与验证依据 |
| --- | --- | --- |
| **模块与声明** | `MODULE`, `EXTENDS` (`Integers`, `Naturals`, `Sequences`, `FiniteSets`, `TLC`), `CONSTANTS`, `VARIABLES`, `ASSUME`, `LOCAL`, `RECURSIVE Op(_, _)` | 支持缩进敏感 `/\` 与 `\/` 列表、多行注释 `(* ... *)` 与单行注释 `\*` |
| **数据与运算符** | 布尔、64 位整数（含 TLA+ 向下取整 `\div` 与正余数 `%`）、字符串、模型值、集合（`UNION`, `SUBSET`, `\cup`, `\cap`, `\`, `\subseteq`, `..`, 集合过滤与映射）、元组/序列（`Len`, `Head`, `Tail`, `Append`, `\o`, `SubSeq`, `SelectSeq`）、函数/记录（`DOMAIN`, `[x \in S |-> e]`, `[S -> T]`, `EXCEPT` 多层路径与 `@`）、`CHOOSE`、`LET ... IN`、`CASE ... OTHER` | 全部值在内部规范化排序后计算 128 位指纹 |
| **动作语义与配置** | `Init`, `Next`, `SPECIFICATION`, `INVARIANT`, `PROPERTY`, `CONSTANT`, `SYMMETRY`, `CHECK_DEADLOCK`, `UNCHANGED`, `ENABLED`, `[Next]_vars` | 单线程确定性 BFS 与官方 TLC 最短反例长度一致 |
| **对称性约简（`0.2.0`）** | `SYMMETRY SymName` + `Permutations(S)`（含多对称集并集） | 对 $|G| \le 120$（如 3–5 个对称节点）计算精确字典序最小轨道规范代表，`TwoPhaseSym` 实测 `288 -> 80` 与 Java TLC `v1.7.4` 逐态一致 |
| **按动作公平性与活性（`0.2.0`）** | 顶层与量化 `WF_v(A)` / `SF_v(A)`（含 `\A p \in S : WF_v(Act(p))`）、`[]P`, `<>P`, `[]<>P`, `P ~> Q`, `[](P => <>Q)`, `\A x \in S : ...` | 采用 Emerson-Lei 迭代 SCC 公平性剪枝算法，与 Java TLC 在 `PetersonLiveness`、`StarvationBuggy`、`TokenRingLiveness` 及 `WF` vs `SF` 单测上 100% 一致 |

## 2. 尚未支持的边界（Honest Known Gaps）

1. **任意嵌套 LTL 公式与通用 Büchi 自动机**：当前活性引擎覆盖最常用的分布式活性模式（`[]P`、`<>P`、`[]<>P`、`P ~> Q`、`[](P => <>Q)` 及外层 `\A` 与 `/\` 组合），暂不支持任意嵌套 `<>[]P` 或带动作谓词的复合时序公式（计划于 `0.3.0` 引入 Tableau/Büchi 自动机补齐）。
2. **对称性约简与活性组合**：与官方 TLC 行为一致，`SYMMETRY` 主要用于安全性（`INVARIANT` / `Deadlock`）加速；同时开启 `SYMMETRY` 与复杂活性公式时建议关闭 `SYMMETRY` 复核。
3. **跨文件 `INSTANCE` 与高阶算子参数**：当前聚焦单文件 `.tla` + `.cfg` 自包含规约，尚未实现外部模块 `INSTANCE M WITH ...` 替换、`Bags` / `Reals` 模块及无限集直接枚举。
4. **超大规模分布式状态空间**：当前为纯内存单线程 BFS，未实现磁盘溢出队列（DiskFPSet）与多线程 Worker 并发探索，适用区间为数万至数十万状态级教学、设计与 CI 回归验证。
