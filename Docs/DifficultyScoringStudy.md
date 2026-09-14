# 难度评分口径调研（Difficulty Scoring Study）

> 状态：**调研记录，结论为"暂不改动 Core"**。本文档记录 2026-09-05 对
> `PuzzleDifficultyAnalyzer`（Core 旧口径）与 step-by-step 脚本新口径的对比实验、
> 数据与结论。**当前不改动 `Sources/CatPuzzleCore` 的任何评分逻辑。**

## 0. 一句话结论

现有数据**不足以支持**把 Core 的 `PuzzleDifficultyAnalyzer` 换成"最难技巧决定 tier"的新口径：
在 Core 真正服务的 6×6 生成场景下，**新口径与旧口径一样饱和**，只是饱和在不同的桶里。
两个口径都缺一个外部 ground truth 来裁决。

## 1. 两个口径是什么

| | 旧口径（Core） | 新口径（脚本） |
|---|---|---|
| 位置 | `Sources/CatPuzzleCore/PuzzleDifficultyAnalyzer.swift` | `Scripts/solve_step_by_step.py` 的 `summarize_difficulty` |
| 公式 | `placedCats + exclusions/10 + deductionRounds×2 + propagationSteps + singleWeight + 各技巧次数×权重` | tier 由整局**最难的一步**决定，score = `最难成本×10 + 步数` |
| tier 阈值 | 绝对分段（`…12 beginner / …22 easy / …35 medium / …50 hard / 其余 expert`），按 6×6 内置关卡标定 | 技巧成本表分段（入门/简单/中等/困难/专家/挑战） |
| 假设的处理 | `assumptionCount > 0` 直接判 `challenge` | 用过试探反证即判"挑战" |

两侧的**技巧集也不完全相同**，对比时需注意：

- 脚本的 `t3_common_attack` 是"色块候选共线"（本质是 size-1 锁定组）；
- Core 的 `commonAttack` 是"某约束的 3+ 候选被同一空格全部攻击"，脚本中对应后补的
  `t5b_common_attack_cell`；
- 脚本会在每一步比较所有可用技巧取最便宜的一步，Core 是固定优先级 first-match。

## 2. 实验一：Docs/demo 真实关卡（n=34）

`Docs/demo/*.PNG` 共 35 个非答案截图，全部是空盘；`219.PNG` 因截图裁剪异常解析失败被跳过。
尺寸分布 8×8 ~ 10×10。

| | 入门 | 简单 | 中等 | 困难 | 专家 | 挑战 |
|---|---|---|---|---|---|---|
| 新口径 | 1 | 4 | 10 | 16 | 0 | 3 |
| 旧口径 | 0 | 0 | 0 | 0 | **31** | 3 |

- tier 一致率 **3/34（9%）**，一致的 3 关全是"挑战"。
- Spearman ρ(new, core) = **+0.822**（9×9 子集 0.964，10×10 子集 0.724）——趋势相关。
- **"是否需要假设"两侧完全一致**：220 / 240 / 260 三关 Core 的 `logicOnly` 为 stuck、
  需要 depth-1 假设，脚本也正是这 3 关用了试探反证。这条判据可靠。
- 最典型的反例是 **248**：全程只用「唯一候选」，是这批里最简单的一关，
  旧口径 66 分 → expert，新口径 29 分 → 入门。

**旧口径在大盘上饱和的原因是确凿的**：score 的前五项（`placedCats`、`exclusions/10`、
`deductionRounds×2`、`propagationSteps`、`singleWeight`）都随盘面尺寸线性增长，
而 tier 阈值 `>50 即 expert` 是按 6×6 标定的。10×10 关卡光是放 10 只猫加传播就轻松破 50。

## 3. 实验二：6×6 生成关卡（n=120）——决定性反证

Core 的评分真正服务的是 `ConstructivePuzzleGenerator` 的 6×6 生成筛选，而 demo 里
一个 6×6 都没有。补跑 `CatPuzzleGenerator --count 120 --seed 7`：

| | 入门 | 简单 | 中等 | 困难 | 专家 |
|---|---|---|---|---|---|
| 新口径 | 4 | 4 | 3 | **109** | 0 |
| 旧口径 | 0 | 0 | 3 | 9 | **108** |

- tier 一致率 **2/120**，ρ(new, core) = **+0.618**。
- 新口径的"最难技巧"分布：共同攻击 82、强链 26、色块共线 4、唯一候选 4、锁定对 3、锁定三 1。
- 这批关卡里 111/120 至少用过一次共同攻击，而新口径**只要用过一次就锁死"困难"**，于是全挤在一格。

**即两个口径在 6×6 上都没有区分度。** 实验一里"新口径分布漂亮"的观感不能外推——
那 34 关只是恰好在尺寸和技巧组合上更分散。

> **样本偏斜提醒**：这 120 个是生成器 mainline **接受**的关卡，生成器本身可能偏好需要
> 高级技巧的布局（`ConstructivePuzzleGenerator` 的 `requiresHardBlueprint`），
> 不是均匀难度样本。

## 4. Ground truth 的缺口

整个调查始终只是**拿两个算法互相比**，没有任何外部难度标签。尝试过用 demo 的文件名
（原游戏关卡编号，游戏内难度通常随编号递增）当弱标签：

| 相关性 | ρ |
|---|---|
| 关卡编号 vs 新口径 score | −0.007 |
| 关卡编号 vs 旧口径 score | +0.150 |
| 关卡编号 vs 盘面尺寸 | +0.600 |

编号在 214–269 这个窄区间里主要与**尺寸**相关，与两个 score 都几乎不相关，**裁决不了**。

## 5. 诊断：两个口径各丢了一半信息

- **旧口径把"规模"当难度**：累加项随尺寸线性增长，阈值又是绝对值。
- **新口径把"是否出现过某技巧"当难度**：一次共同攻击与八次共同攻击同级，
  也不区分这一步是否有更简单的替代路径。

真实难度大概介于两者之间：**最难技巧决定下限，出现频次与不可回避性决定它在桶内的位置。**

## 6. 结论与建议

1. **不要把 Core 换成新口径**（本文档的核心结论）。
2. 若要改进旧口径，最小且有据可依的两处修正是：
   - 把随尺寸线性增长的项按 `size` 归一化；
   - tier 阈值改为随尺寸标定，而不是全局绝对值。
   再把"最难技巧"作为**下限约束**（tier 不低于该技巧对应等级）叠加上去，两边信息都用上。
3. 在拿到外部 ground truth 之前，第 2 条仍是猜测。**最便宜的取得方式**：人工解 10~15 关
   demo 关卡，记录每关耗时与卡壳次数作为标签，再检验两个口径与它的相关性。
   10 关就能把这个问题从"零证据"推到"可判断"。
4. 脚本侧的新口径同样需要改进（6×6 上饱和），它目前的价值是**解释每一步**，不是给出权威难度。

## 7. 复现方式

本次调研新增/改动的研究工具（均不影响 App 与 Core 行为）：

- `Scripts/solve_step_by_step.py`：每步比较全部技巧取最便宜的一步；试探反证挑最短反证链
  并打印完整推理链；输出每步的技巧与难度，以及整局难度汇总。
- `Scripts/compare_difficulty.py`：批量对比两个口径，输出对照表、一致率、分布，`--csv` 可导出。
- `Sources/CatPuzzleGenerator/AnalyzeCommand.swift`：给研究用 CLI 加 `--analyze <json>`，
  **只读**地跑 `LogicalPuzzleSolver` + `PuzzleDifficultyAnalyzer` 并输出 JSON。

```bash
# 实验一：真实关卡截图
python3 Scripts/compare_difficulty.py Docs/demo --csv /tmp/difficulty.csv

# 实验二：6x6 生成关卡
swift run -c release CatPuzzleGenerator --count 120 --seed 7 --json /tmp/gen6.json
python3 Scripts/compare_difficulty.py --generated /tmp/gen6.json --csv /tmp/gen6.csv

# 单关卡的逐步推理（终端 / 可交互 HTML）
python3 Scripts/solve_step_by_step.py Docs/demo/240.PNG --auto
python3 Scripts/solve_step_by_step.py Docs/demo/240.PNG --html /tmp/240.html
```

原始 CSV 是本地产物，未入库；上面的命令可完整重跑出本文的所有数字
（求解器与生成器都是确定性的）。
