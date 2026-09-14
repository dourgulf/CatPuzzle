#!/usr/bin/env python3
"""Compare the step-by-step solver's difficulty rating against Core's.

Research/companion tool (see Docs/GeneratorDesignStudy.md). Two independent
verdicts on the same levels:

  * NEW  -- `solve_step_by_step.py`: picks the cheapest applicable technique
            each turn and rates the level by its single hardest step.
  * CORE -- Swift `LogicalPuzzleSolver` + `PuzzleDifficultyAnalyzer` via
            `swift run CatPuzzleGenerator --analyze`: weighted sum of how
            many times each technique fired.

Levels are read from screenshots (Docs/demo/*.PNG); `*-answer.PNG` images and
anything that fails to parse or has no unique solution are skipped and listed
at the end.

Usage:
    python3 Scripts/compare_difficulty.py Docs/demo
    python3 Scripts/compare_difficulty.py Docs/demo --csv /tmp/difficulty.csv
    python3 Scripts/compare_difficulty.py Docs/demo/214.PNG Docs/demo/233.PNG
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from solve_step_by_step import (  # noqa: E402
    CAT,
    Deducer,
    name_regions,
    difficulty_line,
    parse_board,
    run_deduction,
    solve_exact,
    summarize_difficulty,
)

REPO_ROOT = Path(__file__).resolve().parent.parent

# Core tier -> the script's tier vocabulary, so the two columns are comparable.
CORE_TIER_ZH = {
    "beginner": "入门",
    "easy": "简单",
    "medium": "中等",
    "hard": "困难",
    "expert": "专家",
    "challenge": "挑战",
}
TIER_ORDER = ["入门", "简单", "中等", "困难", "专家", "挑战"]


def level_images(paths: list[Path]) -> list[Path]:
    """Expand directories, drop the `-answer` companions, keep a stable order."""
    images: list[Path] = []
    for path in paths:
        if path.is_dir():
            images.extend(sorted(p for p in path.iterdir()
                                 if p.suffix.lower() in (".png", ".jpg", ".jpeg")))
        else:
            images.append(path)
    return [p for p in images if "-answer" not in p.stem]


def analyze_with_script(image: Path):
    """Run the Python solver on one screenshot from a blank board.

    Returns (record, None) or (None, skip reason). The board layout is taken
    from the screenshot; any cats/exclusions already marked on it are ignored
    so every level is rated from scratch.
    """
    im = Image.open(image).convert("RGB")
    size, region_ids, _states, _bounds, _board, colors = parse_board(im)
    return analyze_level({
        "size": size,
        "regionIDs": region_ids,
        "regionNames": name_regions(colors),
    })


def levels_from_generated(path: Path):
    """Read a `CatPuzzleGenerator --json` batch: Core already scored these, so
    the file supplies both the layouts and the CORE column for free."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    puzzles = payload["puzzles"] if isinstance(payload, dict) else payload
    levels, core_rows = [], {}
    for index, puzzle in enumerate(puzzles):
        level_id = f"seed{puzzle['seed']}-{index + 1}"
        stats = puzzle["statistics"]
        levels.append({"id": level_id, "size": puzzle["size"],
                       "regionIDs": puzzle["regionIDs"]})
        core_rows[level_id] = {
            "id": level_id,
            "score": puzzle["difficulty"]["score"],
            "tier": puzzle["difficulty"]["tier"],
            "logicOnlyStatus": "solved",
            "status": "solved",
            "lockedPair": stats["lockedPairCount"],
            "lockedTriple": stats["lockedTripleCount"],
            "higherOrderLockedSet": stats["higherOrderLockedSetCount"],
            "commonAttack": stats["commonAttackCount"],
            "strongLink": stats["strongLinkDeductionCount"],
            "assumptions": stats["assumptionCount"],
        }
    return levels, core_rows


def analyze_level(level: dict):
    """Score one already-parsed layout with the Python solver.

    `regionNames` is optional: generated levels have no screenshot to read
    colors from, and the difficulty summary never names a Region anyway."""
    size, region_ids = level["size"], level["regionIDs"]
    region_names = level.get("regionNames")
    solutions = solve_exact(size, region_ids, {}, set(), limit=2)
    if not solutions:
        return None, "无解"
    if len(solutions) > 1:
        return None, f"非唯一解（{len(solutions)}+）"
    deducer = Deducer(size, region_ids, [], [], solutions[0], region_names)
    steps, status = run_deduction(deducer, size)
    summary = summarize_difficulty(steps)
    if summary is None:
        return None, "无推理步骤"
    tier, score, hardest = summary
    return {
        "size": size,
        "regionIDs": region_ids,
        "tier": tier,
        "score": score,
        "steps": len(steps),
        "status": status,
        "hardest": hardest["technique"],
        "usedTrial": any(s["technique"] == "试探反证" for s in steps),
        "detail": difficulty_line(steps, status),
    }, None


def analyze_with_core(levels: list[dict], assumption_depth: int) -> dict[str, dict]:
    """Score the same levels with the Swift toolchain, keyed by level id."""
    if not levels:
        return {}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                     encoding="utf-8") as handle:
        json.dump(levels, handle)
        payload = handle.name
    proc = subprocess.run(
        ["swift", "run", "-c", "release", "CatPuzzleGenerator",
         "--analyze", payload, "--assumption-depth", str(assumption_depth)],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"swift run --analyze 失败：\n{proc.stderr}")
    return {row["id"]: row for row in json.loads(proc.stdout)}


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", type=Path, nargs="*",
                        help="Screenshot files, or a directory of them")
    parser.add_argument("--generated", type=Path, default=None,
                        help="Compare a `CatPuzzleGenerator --json` batch instead of screenshots")
    parser.add_argument("--assumption-depth", type=int, default=1,
                        help="Assumption depth for the Core run (default 1, matching the script)")
    parser.add_argument("--csv", type=Path, default=None, help="Also write the table as CSV")
    args = parser.parse_args()

    script_rows: dict[str, dict] = {}
    skipped: list[tuple[str, str]] = []

    if args.generated:
        levels, core_rows = levels_from_generated(args.generated)
        print(f"读入 {len(levels)} 个已生成关卡，运行脚本求解器…", file=sys.stderr)
        for level in levels:
            record, reason = analyze_level(level)
            if record is None:
                skipped.append((level["id"], reason))
            else:
                script_rows[level["id"]] = record
    else:
        images = level_images(args.paths)
        if not images:
            sys.exit("没有找到可用的截图（或改用 --generated）。")
        core_input: list[dict] = []
        print(f"解析 {len(images)} 张截图并运行脚本求解器…", file=sys.stderr)
        for image in images:
            level_id = image.stem
            try:
                record, reason = analyze_with_script(image)
            except Exception as exc:  # research tool: report and move on
                skipped.append((level_id, f"解析失败：{exc}"))
                continue
            if record is None:
                skipped.append((level_id, reason))
                continue
            script_rows[level_id] = record
            core_input.append({
                "id": level_id,
                "size": record["size"],
                "catCount": record["size"],
                "maxMistakes": 3,
                "regionIDs": record["regionIDs"],
            })
        print("运行 Core（swift run CatPuzzleGenerator --analyze）…", file=sys.stderr)
        core_rows = analyze_with_core(core_input, args.assumption_depth)

    header = (f"{'关卡':<8}{'尺寸':<6}{'新口径':<8}{'评分':>5}  "
              f"{'最难技巧':<10}{'Core':<8}{'评分':>5}  {'Core状态':<12}{'一致'}")
    print()
    print(header)
    print("-" * 78)

    agree = 0
    rows_for_csv = []
    for level_id, record in script_rows.items():
        core = core_rows.get(level_id)
        core_tier = CORE_TIER_ZH.get(core["tier"], core["tier"]) if core else "?"
        core_score = core["score"] if core else 0
        core_status = core["logicOnlyStatus"] if core else "?"
        if core and core["logicOnlyStatus"] != "solved":
            core_status = f"{core['logicOnlyStatus']}→{core['status']}"
        same = record["tier"] == core_tier
        agree += 1 if same else 0
        print(f"{level_id:<8}{record['size']}x{record['size']:<3}"
              f"{record['tier']:<8}{record['score']:>5}  "
              f"{record['hardest']:<10}{core_tier:<8}{core_score:>5}  "
              f"{core_status:<12}{'✓' if same else '✗'}")
        rows_for_csv.append({
            "level": level_id,
            "size": record["size"],
            "new_tier": record["tier"],
            "new_score": record["score"],
            "new_steps": record["steps"],
            "new_hardest": record["hardest"],
            "new_used_trial": record["usedTrial"],
            "core_tier": core_tier,
            "core_score": core_score,
            "core_logic_only": core["logicOnlyStatus"] if core else "",
            "core_status": core["status"] if core else "",
            "core_locked_pair": core["lockedPair"] if core else "",
            "core_locked_triple": core["lockedTriple"] if core else "",
            "core_common_attack": core["commonAttack"] if core else "",
            "core_strong_link": core["strongLink"] if core else "",
            "core_assumptions": core["assumptions"] if core else "",
            "tier_agrees": same,
        })

    total = len(script_rows)
    print()
    if total:
        print(f"tier 一致：{agree}/{total}（{agree / total * 100:.0f}%）")
        for label, key in (("新口径", "new"), ("Core", "core")):
            counts = {}
            for row in rows_for_csv:
                counts[row[f"{key}_tier"]] = counts.get(row[f"{key}_tier"], 0) + 1
            spread = "、".join(f"{t} {counts[t]}"
                              for t in TIER_ORDER if t in counts)
            print(f"{label}分布：{spread}")
        trial = sum(1 for r in rows_for_csv if r["new_used_trial"])
        core_assume = sum(1 for r in rows_for_csv if r["core_assumptions"])
        print(f"需要试探反证：脚本 {trial} 关，Core {core_assume} 关")

    if skipped:
        print(f"\n跳过 {len(skipped)} 张：")
        for level_id, reason in skipped:
            print(f"  - {level_id}: {reason}")

    if args.csv:
        import csv
        with args.csv.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows_for_csv[0].keys()))
            writer.writeheader()
            writer.writerows(rows_for_csv)
        print(f"\nCSV 已写入 {args.csv}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
