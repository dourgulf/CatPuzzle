# 生成器算法选型调研（Generator Algorithm Research）

> 状态：**调研方向记录，未定夺**。本文档梳理"同类玩法（LinkedIn Queens / Star Battle 家族）
> 的谜题生成算法空间"，评估当前实现的定位，并列出可能更优的替代方向与待研究问题，
> 供后续逐项深入后再决定是否落地。**当前不改动任何生成器代码。**

## 0. 游戏定位

CatPuzzle 的规则——"每行 / 每列 / 每 Region 恰好一只猫，且任意两只猫不八邻接"——
与 **LinkedIn Queens** 的规则**完全一致（约束同构）**，也与带区域的 **Star Battle 取 k=1
时**的情形**等价**。

> **术语说明（避免误导）**：三者在约束层面同构，但**不存在派生关系**——不应说 LinkedIn
> Queens "是 Star Battle 的变体"（这隐含了不存在的谱系关系）。它们是各自独立命名、约束上
> 殊途同归的游戏。此外 Star Battle（又名 Two Not Touch）的**主流形态是 2★**，1★ 反而少见，
> 因此更准确的表述是"三者规则等价 / 同构"，而非谁包含谁。

正因约束同构，这几个游戏成熟的求解 / 生成研究成果都可直接互相借鉴。

## 1. 当前算法的定位

当前流水线（`ConstructivePuzzleGenerator.generate`）是三段式：

1. **先种随机合法解**（`SolutionPermutationGenerator`）
2. **围绕解构造区域**（`RegionPartition.build`：级联 / 泛洪 + 几何画像校验）
3. **求解器认证**：`PuzzleSolver`（自研 exact MRV search）证唯一 +
   `LogicalPuzzleSolver` 产出可解释技巧序列，`DeductionBlueprint` 按难度门禁

**判断**：这是该家族的**主流最佳实践骨架**，方向正确。相比多数开源实现（通常只做到
"能解 + 唯一性"），本项目多了一层**可解释技巧分级 + 蓝图门禁**，这是把"随机合法谜题"
变成"难度可控、人类可推理谜题"的关键，完成度高于多数实现。

**两个已知痛点**（本次 10x10 Easy 调查中暴露）：

- **逐候选逻辑求解昂贵**：每个候选都要跑一遍 `LogicalPuzzleSolver`，10x10 上单次数百毫秒。
- **良率低 + 失败烧预算**：区域"随机构造 → blueprint 事后过滤"，10x10 Easy 命中率 ~37%，
  失败的 seed 会耗尽逻辑求解预算（4–8s）才放弃。

## 2. 算法空间（发散）

| 范式 | 说明 | 与本游戏的适配 |
|---|---|---|
| 生成-测试 / 拒绝采样 | 纯随机造盘再验 | 最朴素，良率极低，不可取 |
| **先解后构造 + 认证**（当前） | 种解 → 长区域 → 验唯一 | 主流、稳健，已采用 |
| 引导式构造（Boltzmann） | 用"当前所有替代解的分布"决定下一步加哪个约束 | ⭐ 提良率，见 §3.2 |
| SAT / CP / IP 驱动 | Z3、CLP(FD)、整数规划求解 + 唯一性判定 | ⭐ 提速，见 §3.1 |
| 雕刻法 carving | 从满约束逐步移除线索到临界唯一（数独式） | 部分适用：given-anchor 可用此思路 |
| 元启发式（遗传 / 模拟退火） | 以难度评分为适应度函数搜索 | 精确命中难度 tier，但慢，适合离线批量 |

## 3. 两个重点升级方向（对应上述痛点）

### 3.1 唯一性认证：SAT / CP 替代自研 exact search

- **标准技巧**："求一个解 → 加一条『排除该解』的子句 → 再求一次；若 UNSAT 则唯一。"
- **依据**：Star Battle 社区明确指出朴素回溯解 10x10 太慢、需改用 CLP(FD)；
  LinkedIn Queens 普遍用 Z3 / 整数规划（IP）。现成 SAT/CP 求解器通常比自研搜索
  快 1–2 个数量级，直接缓解"每候选都跑一遍很贵"。
- **架构权衡（重要）**：`Sources/CatPuzzleCore` 是**纯 Swift、无第三方依赖**的硬边界。
  引入 SAT/CP 意味着要么打破该边界（引第三方 solver），要么**自己在 Core 内写一个
  小型 SAT/DPLL 或 exact-cover(DLX)**。后者可保持纯净但有实现成本。
- **待研究问题**：
  - [ ] 自写 DLX（Dancing Links / exact-cover）能否覆盖"无八邻接"这类非精确覆盖约束？
        （行/列/区是精确覆盖，邻接约束需额外处理，可能更适合 SAT 而非纯 DLX）
  - [ ] 纯 Swift 小型 SAT/CP 的实现成本 vs. 现有 exact MRV search 的实际加速比？
  - [ ] 是否只在"认证"环节替换、`LogicalPuzzleSolver`（分级用）保持不变即可？

### 3.2 区域构造：从"随机 + 过滤"升级为"引导式"

- **现状**：随机长区域 → `DeductionBlueprint` 事后否掉大多数 → 良率靠撞运气，失败还白跑求解。
- **业界做法（battlestar，region-less Star Battle 生成器）**：**引导式构造**——每一步用
  "当前盘面所有替代解的星频率分布"（按 Boltzmann 温度采样）决定下一个约束放哪，
  每步都朝"消除最多歧义"走；温度参数控制线索密度 / 结构。
- **移植设想**：区域生长时优先切分**"当前多解中分歧最大的格子"**，并让难度目标
  （如 Easy 想少 locked pair）反过来引导切法，把过滤逻辑**前移为引导**，
  使候选"大概率一次成型"。
- **待研究问题**：
  - [ ] battlestar 是 region-less（线索是 block 而非彩色区），其 Boltzmann 思路如何映射到
        "彩色区域切分"这种线索形式？
  - [ ] "枚举当前替代解分布"本身可能很贵——是否需要近似（采样 K 个替代解而非全枚举）？
  - [ ] 引导构造与现有 `EvaluatedCandidate` 束搜索排名如何整合（引导 vs. 事后排序）？

## 4. 其他可选方向（备忘）

- **雕刻法用于 given-anchor**：当前 given-anchor 是"从唯一解里挑 N 格预置"。
  可考虑数独式雕刻——从"全解可见"逐步隐藏格子直到临界唯一，控制开局线索量。
- **元启发式精调难度**：离线批量生成关卡库时，用遗传 / 模拟退火以
  `PuzzleDifficultyAnalyzer` 评分为适应度，精确命中目标 tier。慢，但离线无所谓。

## 5. 按场景选型（初步结论）

- **离线预烘焙关卡库**（最可能的场景）：当前方法已够用且接近最优；良率低可用"多跑 seed"
  掩盖。想更好则叠加 §3.1 提速 + §3.2 提良率，甚至用 §4 元启发式精调难度。
- **运行时即时生成**：必须快 → §3.1 + §3.2 是刚需；或干脆预生成库、运行时随机取。

**一句话**：不是"换算法"，而是**认证换 SAT/CP 提速、区域构造从『随机+过滤』升级为『引导式』
提良率**——前提是想清楚是否愿意为此在纯净的 Core 层引入 / 自写求解器。

## 6. Star Battle 1★ 专门资料速览

CatPuzzle 的约束与 LinkedIn Queens **同构**，也与 **Star Battle 取 k=1** 时的情形**等价**
（Star Battle 通用形式是每行 / 列 / 区放 k 个星，k=1/2/3，主流为 2★；我们对应 k=1）。三者是
约束等价而非派生关系（见 §0 术语说明）。正因逐条约束完全对应（每行 / 列 / 区恰好一个 +
不能八邻接），Star Battle k=1 的求解 / 生成研究可直接借鉴。几个直接支撑本调研判断的工程事实：

- **求解性能佐证（支撑 §3.1 换 CP/SAT）**：`mmachenry/star-battle` 记录朴素回溯解一个
  10x10 Star Battle **需一天以上**，改写为 CLP(FD)（有限域约束逻辑编程）后降到 **~90 秒**。
  数量级差异说明：规模上升后，约束求解范式（CP/SAT）远优于朴素回溯。
  （注：本项目的 exact MRV + bitset 已远好于"朴素回溯"，但该对比印证了范式选择的价值。）

- **SAT / CP 编码要点（§3.1 落地参考）**：
  - "每行 / 每列 / 每区恰好一个星" = **exactly-one** 约束 = at-least-one 子句 +
    **at-most-one** 编码（naive pairwise、commander、sequential 等编码各有取舍）。
  - "不能八邻接" = 每对相邻格的**二元互斥**子句。
  - **唯一性判定**（我们最需要的）= 求一个模型 → 加一条"排除该模型"的子句 → 再求；
    第二次 UNSAT 即唯一。这是 SAT/CP 判唯一的标准套路。

- **人类求解技巧体系（对照校准我们的 `LogicalPuzzleSolver` 与难度分级）**：
  Alex Boisvert 的 "Solving Star Battle Puzzles" 系统梳理了 Star Battle 的人类推理技巧
  （区域 / 行列的 at-most-one 推导、块排除、区域包含 / 排斥等）。可用来核对我们的技巧集
  是否完整、以及各技巧的难度权重是否贴近人类感知。

- **复杂度定位**：Star Battle 属组合搜索型约束满足问题，规模上升后朴素回溯不可行，
  这正是社区转向 CP / SAT / IP 的原因（未检索到公开的严格 NP-complete 证明，此处不作断言）。

- **对照实现**：`cosmologicon/constraint-examples` 用 python-constraint（CSP 库）直接解
  Star Battle，可作为"用现成约束求解器替代自研搜索"的最小对照参考。

## 7. 参考来源

**同款（LinkedIn Queens）**

- [LinkedIn Queens solver（回溯 + CV）](https://github.com/SebiCoroian/LinkedInQueensGameSolver)
- [用整数规划解 LinkedIn Queens](https://medium.com/@rihot_gusron/an-integer-programming-approach-to-linkedins-new-queen-puzzle-17fe27a5e2ed)
- [用 SAS PROC OPTMODEL 解 Queens](https://communities.sas.com/t5/SAS-Communities-Library/Solving-the-LinkedIn-Queens-Puzzle-with-PROC-OPTMODEL/ta-p/957025)

**同族（Star Battle 1★）**

- [battlestar — Boltzmann 引导式 Star Battle 生成器](https://github.com/MeepMoop/battlestar)
- [mmachenry/star-battle — 朴素回溯 >1 天、CLP(FD) ~90 秒](https://github.com/mmachenry/star-battle)
- [Alex Boisvert — Solving Star Battle Puzzles（人类求解技巧体系）](https://alexboisvert.com/musings/2018/01/16/solving-star-battle-puzzles/)
- [cosmologicon/constraint-examples — python-constraint 解 Star Battle](https://github.com/cosmologicon/constraint-examples)
