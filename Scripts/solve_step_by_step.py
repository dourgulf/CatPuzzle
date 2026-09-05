#!/usr/bin/env python3
"""Step-by-step human-style solver for an in-progress CatPuzzle screenshot.

Research/companion tool (see Docs/GeneratorDesignStudy.md; the Docs/demo
screenshots and this Scripts/ folder stay local and out of version control).

Given a screenshot of a level that may be blank OR partially solved -- some
cells already carry a placed cat, some carry an X (excluded) mark, the rest
are empty -- this tool:

  1. Parses the board (region layout + cat/excluded marks) by pixel color,
     reusing transcribe_level.py's detection.
  2. Certifies the level's unique solution with a backtracking exact solver,
     seeding it with the detected cats (which the user guarantees correct).
     Any detected `excluded` cell that is actually a cat in the unique
     solution is reported as a MISLABELED mark and corrected before solving.
  3. Runs a deterministic, human-style deduction loop from the (corrected)
     state, emitting one technique application at a time with its reasoning
     and the new cat/excluded marks it produced, pausing for a keypress
     between steps (use --auto to run straight through).

Rules recap: exactly one cat per row, per column, and per color region;
cats may never touch, including diagonally.

Coordinates are printed 1-based as R<row>C<col>, row 1 = top, col 1 = left.

Usage:
    python3 Scripts/solve_step_by_step.py ~/Downloads/level.png
    python3 Scripts/solve_step_by_step.py ~/Downloads/level.png --auto
    python3 Scripts/solve_step_by_step.py ~/Downloads/level.png --debug-image /tmp/parsed.png
"""

from __future__ import annotations

import argparse
import copy
import sys
from itertools import combinations
from pathlib import Path

from PIL import Image, ImageDraw

from transcribe_level import (
    BoardBounds,
    cell_rects,
    color_distance,
    find_board_bounds,
    find_cell_boundaries,
)
from transcribe_solution import classify_cell

REGION_MERGE_DISTANCE = 40.0

# Largest locked set (N units confined to N cross-units) the deducer will try.
# CatPuzzleCore's LogicalPuzzleSolver caps at 3 (lockedPair/lockedTriple); the
# large Docs/demo boards (e.g. Level 258) empirically need one k=4 step, so the
# teaching script goes a little further before falling back to a trial.
MAX_LOCKED_SET = 4


def region_color(im: Image.Image, rect: tuple[int, int, int, int]) -> tuple[int, int, int]:
    """Robust underlying region color for a cell that may carry an X or a cat.

    transcribe_level.sample_cell is tuned for un-overlaid blank levels; the
    white X stroke and black cat fur bleed into its corner samples and split
    one region into several IDs. Here we densely sample the cell interior,
    drop near-white (X) and near-black (cat) pixels, and take the per-channel
    median of what remains -- the flat region color the mark sits on.
    """
    px = im.load()
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    ix0, iy0 = x0 + int(w * 0.12), y0 + int(h * 0.12)
    ix1, iy1 = x1 - int(w * 0.12), y1 - int(h * 0.12)
    rs, gs, bs = [], [], []
    for y in range(iy0, iy1, 2):
        for x in range(ix0, ix1, 2):
            r, g, b = px[x, y]
            if r > 230 and g > 230 and b > 230:  # white X stroke
                continue
            if r < 70 and g < 70 and b < 70:  # black cat fur / outline
                continue
            rs.append(r)
            gs.append(g)
            bs.append(b)
    if not rs:  # glyph covered every sample; fall back to the raw center pixel
        return px[(x0 + x1) // 2, (y0 + y1) // 2]

    def median(vals: list[int]) -> int:
        vals.sort()
        return vals[len(vals) // 2]

    return (median(rs), median(gs), median(bs))

CAT = "cat"
EXCLUDED = "excluded"
UNKNOWN = "unknown"


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

def crop_board(im: Image.Image) -> tuple[Image.Image, BoardBounds]:
    """Two-stage board isolation: locate the board in the full screenshot,
    then crop to it so the header rule-icons and footer buttons cannot bias
    the later grid detection or cell sampling. Returns the cropped board image
    and the (tight) bounds *within that crop*.
    """
    coarse = find_board_bounds(im)
    board = im.crop((coarse.x0, coarse.y0, coarse.x1 + 1, coarse.y1 + 1))
    tight = find_board_bounds(board)  # nearly full-frame; trims any margin
    return board, tight


def parse_board(im: Image.Image):
    """Return (size, region_ids, states, bounds, board).

    states[r][c] is one of 'cat' / 'excluded' / 'empty' as drawn.
    region_ids are clustered from each cell's robust (X/cat-resistant) color.
    All work happens on the cropped board image so header/footer content is
    physically excluded from every measurement.
    """
    board, bounds = crop_board(im)
    im = board
    x_bounds = find_cell_boundaries(im, bounds, axis="x")
    y_bounds = find_cell_boundaries(im, bounds, axis="y")
    cols, rows = len(x_bounds) - 1, len(y_bounds) - 1
    if rows != cols:
        raise ValueError(
            f"Detected non-square grid ({rows}x{cols}); check the screenshot crop."
        )
    rects = cell_rects(x_bounds, y_bounds)

    states = [[classify_cell(im, rects[r][c]) for c in range(cols)] for r in range(rows)]

    region_ids = [[-1] * cols for _ in range(rows)]
    region_colors: dict[int, tuple[int, int, int]] = {}
    for r in range(rows):
        for c in range(cols):
            color = region_color(im, rects[r][c])
            match = None
            for rid, known in region_colors.items():
                if color_distance(color, known) <= REGION_MERGE_DISTANCE:
                    match = rid
                    break
            if match is None:
                match = len(region_colors)
                region_colors[match] = color
            region_ids[r][c] = match

    return rows, region_ids, states, bounds, board, region_colors


# --------------------------------------------------------------------------
# Exact solver (uniqueness + ground truth for validation)
# --------------------------------------------------------------------------

def solve_exact(size, region_ids, forced_cats, forced_excluded, limit=2):
    """Backtracking solver, one cat per row. Returns up to `limit` solutions,
    each a list `cols` where cols[r] is the cat column in row r.

    forced_cats: {row: col} cells that must hold a cat.
    forced_excluded: set of (r, c) cells that may not hold a cat.
    """
    solutions: list[list[int]] = []
    cols_used = set()
    regions_used = set()
    placement = [-1] * size

    def place(r):
        if len(solutions) >= limit:
            return
        if r == size:
            solutions.append(placement.copy())
            return
        candidates = range(size)
        if r in forced_cats:
            candidates = [forced_cats[r]]
        for c in candidates:
            if c in cols_used:
                continue
            reg = region_ids[r][c]
            if reg in regions_used:
                continue
            if (r, c) in forced_excluded:
                continue
            if r > 0 and placement[r - 1] in (c - 1, c, c + 1):
                continue
            placement[r] = c
            cols_used.add(c)
            regions_used.add(reg)
            place(r + 1)
            placement[r] = -1
            cols_used.discard(c)
            regions_used.discard(reg)
            if len(solutions) >= limit:
                return

    place(0)
    return solutions


# --------------------------------------------------------------------------
# Human-style deduction engine
# --------------------------------------------------------------------------

class Deducer:
    def __init__(self, size, region_ids, cats, excluded, solution):
        self.size = size
        self.region_ids = region_ids
        # grid[r][c] in {CAT, EXCLUDED, UNKNOWN}
        self.grid = [[UNKNOWN] * size for _ in range(size)]
        for (r, c) in cats:
            self.grid[r][c] = CAT
        for (r, c) in excluded:
            self.grid[r][c] = EXCLUDED
        self.solution = solution  # cols[r]; used only for defensive checks
        # region -> list of cells
        self.region_cells: dict[int, list[tuple[int, int]]] = {}
        for r in range(size):
            for c in range(size):
                self.region_cells.setdefault(region_ids[r][c], []).append((r, c))

    # -- helpers -----------------------------------------------------------

    def units(self):
        """Yield ('row'|'column'|'color', label, [cells])."""
        n = self.size
        for r in range(n):
            yield ("row", r + 1, [(r, c) for c in range(n)])
        for c in range(n):
            yield ("column", c + 1, [(r, c) for r in range(n)])
        for rid, cells in sorted(self.region_cells.items()):
            yield ("color", rid, cells)

    def candidates(self, cells):
        return [(r, c) for (r, c) in cells if self.grid[r][c] == UNKNOWN]

    def has_cat(self, cells):
        return any(self.grid[r][c] == CAT for (r, c) in cells)

    def place_cat(self, r, c):
        assert self.solution[r] == c, f"BUG: placed cat R{r+1}C{c+1} contradicts unique solution"
        self.grid[r][c] = CAT

    def exclude(self, r, c):
        assert self.solution[r] != c, f"BUG: excluded R{r+1}C{c+1} that is a cat in the unique solution"
        self.grid[r][c] = EXCLUDED

    def solved(self):
        return sum(row.count(CAT) for row in self.grid) == self.size

    # -- techniques --------------------------------------------------------
    # Each returns (description, [('cat'|'excluded', r, c), ...]) or None.

    def t1_eliminate_from_cats(self):
        """A placed cat forbids its row, column, region, and 8 neighbors."""
        n = self.size
        for r in range(n):
            for c in range(n):
                if self.grid[r][c] != CAT:
                    continue
                new = []
                affected = set()
                for cc in range(n):
                    affected.add((r, cc))
                for rr in range(n):
                    affected.add((rr, c))
                for cell in self.region_cells[self.region_ids[r][c]]:
                    affected.add(cell)
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        affected.add((r + dr, c + dc))
                for (rr, cc) in affected:
                    if 0 <= rr < n and 0 <= cc < n and self.grid[rr][cc] == UNKNOWN:
                        new.append((EXCLUDED, rr, cc))
                if new:
                    desc = (
                        f"R{r+1}C{c+1} 已是猫：按“每行/列/同色只有一只”且“猫不相邻”，"
                        f"排除与它同行、同列、同色或相邻的所有空格。"
                    )
                    return desc, new
        return None

    def t2_hidden_single(self):
        """A unit with exactly one remaining candidate places a cat there."""
        for kind, label, cells in self.units():
            if self.has_cat(cells):
                continue
            cand = self.candidates(cells)
            if len(cand) == 1:
                r, c = cand[0]
                name = {"row": f"第 {label} 行", "column": f"第 {label} 列", "color": f"{label} 号色块"}[kind]
                desc = f"{name}的其他格都已被排除，唯一能放猫的位置是 R{r+1}C{c+1}。"
                return desc, [(CAT, r, c)]
        return None

    def t3_common_attack(self):
        """If every candidate of a color region shares one row (or column),
        that row (column) must hold this region's cat -> exclude the rest."""
        n = self.size
        for rid, cells in sorted(self.region_cells.items()):
            if self.has_cat(cells):
                continue
            cand = self.candidates(cells)
            if len(cand) < 2:
                continue
            rows = {r for (r, _c) in cand}
            cols = {c for (_r, c) in cand}
            if len(rows) == 1:
                r = next(iter(rows))
                new = [(EXCLUDED, r, c) for c in range(n)
                       if self.grid[r][c] == UNKNOWN and self.region_ids[r][c] != rid]
                if new:
                    desc = (f"{rid} 号色块的候选格全部落在第 {r+1} 行，"
                            f"故这只猫必在第 {r+1} 行 → 排除该行其他色块的空格。")
                    return desc, new
            if len(cols) == 1:
                c = next(iter(cols))
                new = [(EXCLUDED, r, c) for r in range(n)
                       if self.grid[r][c] == UNKNOWN and self.region_ids[r][c] != rid]
                if new:
                    desc = (f"{rid} 号色块的候选格全部落在第 {c+1} 列，"
                            f"故这只猫必在第 {c+1} 列 → 排除该列其他色块的空格。")
                    return desc, new
        return None

    # -- helpers for the advanced techniques ------------------------------

    def _unit_kind(self, r, c, family):
        """The label of the row/column/region unit cell (r,c) belongs to."""
        if family == "row":
            return ("row", r)
        if family == "column":
            return ("column", c)
        return ("color", self.region_ids[r][c])

    def _cells_of_kind(self, kind):
        tag, label = kind
        n = self.size
        if tag == "row":
            return [(label, c) for c in range(n)]
        if tag == "column":
            return [(r, label) for r in range(n)]
        return list(self.region_cells[label])

    def _unresolved_units(self, family):
        """Units of a family that still need a cat, with their candidate cells."""
        result = []
        for kind, _label, cells in self.units():
            fam = {"row": "row", "column": "column", "color": "region"}[kind]
            if fam != family:
                continue
            if self.has_cat(cells):
                continue
            cand = self.candidates(cells)
            if cand:
                result.append((kind, _label, cand))
        return result

    def _attacks(self, a, b):
        """True if a cat on cell a would forbid cell b (same row/col/region or 8-adjacent)."""
        (r1, c1), (r2, c2) = a, b
        if a == b:
            return False
        if r1 == r2 or c1 == c2:
            return True
        if self.region_ids[r1][c1] == self.region_ids[r2][c2]:
            return True
        return abs(r1 - r2) <= 1 and abs(c1 - c2) <= 1

    _FAMILY_NAME = {"row": "行", "column": "列", "region": "色块"}

    def t4_locked_set(self):
        """Generalized locked set (pigeonhole). If N source units confine their
        candidates to exactly N cross-units, those cross-units are 'owned' -> any
        other candidate in them is excluded. N=1 across region->line is the
        common attack (t3); this covers N=2..MAX for every source/target family
        pair (region<->row/column, row<->column), mirroring Core's lockedSet."""
        families = ("row", "column", "region")
        for size in range(2, MAX_LOCKED_SET + 1):
            for src_fam in families:
                for tgt_fam in families:
                    if src_fam == tgt_fam:
                        continue
                    sources = self._unresolved_units(src_fam)
                    if len(sources) < size:
                        continue
                    for combo in combinations(sources, size):
                        union = [cell for _k, _l, cand in combo for cell in cand]
                        target_kinds = {self._unit_kind(r, c, tgt_fam) for (r, c) in union}
                        if len(target_kinds) != size:
                            continue
                        union_set = set(union)
                        new = []
                        for kind in sorted(target_kinds):
                            for (r, c) in self._cells_of_kind(kind):
                                if self.grid[r][c] == UNKNOWN and (r, c) not in union_set:
                                    new.append((EXCLUDED, r, c))
                        if new:
                            src_labels = ", ".join(str(l) for _k, l, _c in combo)
                            tgt_labels = ", ".join(str(l) for _t, l in sorted(target_kinds))
                            noun = "对" if size == 2 else "组"
                            desc = (
                                f"锁定{noun}：{size} 个{self._FAMILY_NAME[src_fam]}"
                                f"（{src_labels}）的候选恰好只占据 {size} 个"
                                f"{self._FAMILY_NAME[tgt_fam]}（{tgt_labels}）"
                                f"→ 这些{self._FAMILY_NAME[tgt_fam]}被它们包干，排除其中其余空格。"
                            )
                            return desc, new
        return None

    def t5_strong_link(self):
        """A unit with exactly two candidates A, B must hold its cat on one of
        them; any cell attacked by BOTH A and B can never be a cat -> exclude."""
        for kind, label, cells in self.units():
            if self.has_cat(cells):
                continue
            cand = self.candidates(cells)
            if len(cand) != 2:
                continue
            a, b = cand
            new = []
            for r in range(self.size):
                for c in range(self.size):
                    if self.grid[r][c] != UNKNOWN or (r, c) in (a, b):
                        continue
                    if self._attacks(a, (r, c)) and self._attacks(b, (r, c)):
                        new.append((EXCLUDED, r, c))
            if new:
                name = {"row": f"第 {label} 行", "column": f"第 {label} 列",
                        "color": f"{label} 号色块"}[kind]
                desc = (
                    f"强链：{name}只剩 R{a[0]+1}C{a[1]+1}、R{b[0]+1}C{b[1]+1} 两个候选，"
                    f"猫必居其一 → 同时被两者攻击的空格都不可能是猫，排除。"
                )
                return desc, new
        return None

    # -- depth-1 assumption (proof by contradiction) ----------------------

    def _polynomial_step(self):
        """First deterministic (non-assumption) technique that fires, or None."""
        for technique in (self.t1_eliminate_from_cats, self.t2_hidden_single,
                           self.t3_common_attack, self.t4_locked_set, self.t5_strong_link):
            result = technique()
            if result:
                return result
        return None

    def _has_contradiction(self):
        for _kind, _label, cells in self.units():
            if not self.has_cat(cells) and not self.candidates(cells):
                return True
        return False

    def _run_to_fixpoint(self):
        """Apply polynomial techniques (raw, no solution asserts) until stuck or
        a contradiction appears. Returns True if consistent, False if broken.
        Used only on throwaway copies inside t6_assumption."""
        while True:
            if self._has_contradiction():
                return False
            result = self._polynomial_step()
            if result is None:
                return not self._has_contradiction()
            for kind, r, c in result[1]:
                self.grid[r][c] = kind

    def t6_assumption(self):
        """Depth-1 trial: if hypothesizing a cat on an unknown cell forces a
        contradiction under the polynomial techniques, that cell can't be a cat."""
        for r in range(self.size):
            for c in range(self.size):
                if self.grid[r][c] != UNKNOWN:
                    continue
                trial = copy.deepcopy(self)
                trial.grid[r][c] = CAT
                if not trial._run_to_fixpoint():
                    desc = (
                        f"试探反证：假设 R{r+1}C{c+1} 放猫，仅凭确定性推理即可推出矛盾"
                        f"（某行/列/色块再无处落猫）→ 故 R{r+1}C{c+1} 必为空。"
                    )
                    return desc, [(EXCLUDED, r, c)]
        return None

    def next_step(self):
        for technique in (self.t1_eliminate_from_cats, self.t2_hidden_single,
                          self.t3_common_attack, self.t4_locked_set,
                          self.t5_strong_link, self.t6_assumption):
            result = technique()
            if result:
                return result
        return None

    def apply(self, marks):
        for kind, r, c in marks:
            if kind == CAT:
                self.place_cat(r, c)
            else:
                self.exclude(r, c)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def render_debug(im, bounds, size, region_ids, states, out_path):
    annotated = im.convert("RGB").copy()
    draw = ImageDraw.Draw(annotated)
    cw = (bounds.x1 - bounds.x0) / size
    ch = (bounds.y1 - bounds.y0) / size
    ring = {"cat": (0, 90, 255), "excluded": (0, 170, 0), "empty": (220, 0, 0)}
    for r in range(size):
        for c in range(size):
            x0 = bounds.x0 + int(c * cw)
            y0 = bounds.y0 + int(r * ch)
            x1 = bounds.x0 + int((c + 1) * cw)
            y1 = bounds.y0 + int((r + 1) * ch)
            draw.rectangle([x0, y0, x1, y1], outline=ring[states[r][c]], width=3)
            draw.text((x0 + 4, y0 + 4), str(region_ids[r][c]), fill=(0, 0, 0))
    annotated.save(out_path)


def board_str(size, region_ids, grid):
    """ASCII snapshot: C=cat, .=excluded, digit=region of an unknown cell."""
    lines = []
    for r in range(size):
        row = []
        for c in range(size):
            if grid[r][c] == CAT:
                row.append(" C")
            elif grid[r][c] == EXCLUDED:
                row.append(" .")
            else:
                row.append(f"{region_ids[r][c]:2d}")
        lines.append("".join(row))
    return "\n".join(lines)


def _glyph(state, region_id):
    if state == CAT:
        return "C"
    if state == EXCLUDED:
        return "x"
    return str(region_id) if region_id < 10 else "#"


def render_board(size, region_ids, grid, region_colors, new_cells, use_color=True):
    """Board snapshot. In color mode each cell's background is its true region
    color (so the layout reads like the screenshot), with C/x/region-digit on
    top; cells changed on this step are shown bold + reverse-highlighted."""
    lines = []
    for r in range(size):
        parts = []
        for c in range(size):
            state = grid[r][c]
            is_new = (r, c) in new_cells
            if use_color:
                # The background already conveys the region, so an unknown
                # cell shows nothing -- only cats/exclusions carry a glyph.
                ch = "C" if state == CAT else "x" if state == EXCLUDED else " "
                if is_new and state == CAT:
                    sgr = "1;48;2;0;170;0;38;2;255;255;255"    # this step's new cat: green bg
                elif is_new and state == EXCLUDED:
                    sgr = "1;48;2;215;55;55;38;2;255;255;255"  # this step's new exclusion: red bg
                else:
                    br, bg, bb = region_colors.get(region_ids[r][c], (200, 200, 200))
                    lum = 0.299 * br + 0.587 * bg + 0.114 * bb
                    fr, fg, fb = (0, 0, 0) if lum > 140 else (255, 255, 255)
                    sgr = f"48;2;{br};{bg};{bb};38;2;{fr};{fg};{fb}"
                # Two chars wide per cell: at the terminal's ~1:2 glyph aspect
                # ratio this keeps a 10x10 board visually square (20 cols x 10
                # rows). A third column would make it noticeably wide.
                parts.append(f"\x1b[{sgr}m {ch}\x1b[0m")
            else:
                # No color: keep the region digit so regions stay legible.
                ch = _glyph(state, region_ids[r][c])
                parts.append(f"{'*' if is_new else ' '}{ch}")
        lines.append("".join(parts))
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Deduction driver (shared by terminal and HTML output)
# --------------------------------------------------------------------------

def run_deduction(deducer: "Deducer", size: int):
    """Run techniques to exhaustion, returning (steps, status).

    Each step is {'desc', 'marks', 'grid'} where 'grid' is a snapshot of the
    board *after* the step. status is 'solved' or 'stuck'.
    """
    steps = []
    while not deducer.solved():
        result = deducer.next_step()
        if result is None:
            return steps, "stuck"
        desc, marks = result
        deducer.apply(marks)
        steps.append({
            "desc": desc,
            "marks": marks,
            "grid": [row[:] for row in deducer.grid],
        })
    return steps, "solved"


# --------------------------------------------------------------------------
# HTML output
# --------------------------------------------------------------------------

_ENC = {UNKNOWN: 0, CAT: 1, EXCLUDED: 2}

HTML_TEMPLATE = r"""<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CatPuzzle 逐步求解</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 -apple-system, "Segoe UI", system-ui, sans-serif;
         background: #f4f1ee; color: #2b2320; }
  @media (prefers-color-scheme: dark) { body { background: #1c1a18; color: #eee; } }
  header { display: flex; align-items: baseline; gap: 12px; padding: 16px 20px 4px; }
  h1 { font-size: 18px; margin: 0; }
  .badge { font-size: 12px; padding: 2px 8px; border-radius: 10px; background: #2e7d32; color: #fff; }
  .badge.stuck { background: #c0392b; }
  #note { padding: 0 20px; color: #b5651d; font-size: 13px; }
  .layout { display: flex; flex-wrap: wrap; gap: 20px; padding: 12px 20px 28px; align-items: flex-start; }
  .board-wrap { flex: 0 0 auto; }
  #board { display: grid; gap: 2px; background: rgba(0,0,0,.15); padding: 2px; border-radius: 8px; }
  .cell { width: 40px; height: 40px; display: flex; align-items: center; justify-content: center;
          font-size: 22px; border-radius: 4px; position: relative; user-select: none; }
  .cell .x { color: rgba(255,255,255,.9); font-size: 20px; font-weight: 700;
             text-shadow: 0 1px 1px rgba(0,0,0,.35); }
  .cell.newcat { box-shadow: inset 0 0 0 3px #14b814, 0 0 8px #14b814; }
  .cell.newexc { box-shadow: inset 0 0 0 3px #e23b3b; }
  .panel { flex: 1 1 300px; min-width: 280px; }
  .stepline { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
  .stepline button { font: inherit; padding: 6px 12px; border-radius: 8px; border: 1px solid #999;
                     background: #fff; cursor: pointer; }
  @media (prefers-color-scheme: dark) { .stepline button { background: #333; color: #eee; border-color: #555; } }
  .stepline button:disabled { opacity: .4; cursor: default; }
  #counter { font-variant-numeric: tabular-nums; min-width: 120px; }
  #desc { font-size: 15px; min-height: 3em; padding: 10px 12px; border-radius: 8px;
          background: rgba(0,0,0,.05); }
  @media (prefers-color-scheme: dark) { #desc { background: rgba(255,255,255,.08); } }
  #marks { list-style: none; padding: 0; margin: 10px 0; font-size: 13px; }
  #marks li { display: inline-block; margin: 2px 6px 2px 0; padding: 1px 7px; border-radius: 6px; }
  #marks li.cat { background: rgba(20,184,20,.18); }
  #marks li.exc { background: rgba(226,59,59,.16); }
  .legend { margin-top: 16px; font-size: 12px; color: #777; }
</style>
</head>
<body>
<div id="app">
  <header><h1 id="title"></h1><span id="status" class="badge"></span></header>
  <div id="note"></div>
  <div class="layout">
    <div class="board-wrap"><div id="board"></div></div>
    <aside class="panel">
      <div class="stepline">
        <button id="prev">← 上一步</button>
        <span id="counter"></span>
        <button id="next">下一步 →</button>
      </div>
      <p id="desc"></p>
      <ul id="marks"></ul>
      <div class="legend">🐱 猫　✕ 排除　绿框=本步新增猫　红框=本步新增排除　（← → 键可翻页）</div>
    </aside>
  </div>
</div>
<script>
const DATA = __DATA__;
const { size, regionIds, regionColors, frames, status, title } = DATA;
let i = 0;

const boardEl = document.getElementById("board");
boardEl.style.gridTemplateColumns = `repeat(${size}, 40px)`;
document.getElementById("title").textContent = title;
const statusEl = document.getElementById("status");
statusEl.textContent = status === "solved" ? "已解出" : "需更高级技巧";
if (status !== "solved") statusEl.classList.add("stuck");
const note = DATA.note;
if (note) document.getElementById("note").textContent = note;

function key(r, c) { return r + "," + c; }

function render() {
  const f = frames[i];
  const newCat = new Set(f.newCats.map(([r, c]) => key(r, c)));
  const newExc = new Set(f.newExcluded.map(([r, c]) => key(r, c)));
  boardEl.innerHTML = "";
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      const div = document.createElement("div");
      div.className = "cell";
      const col = regionColors[regionIds[r][c]];
      div.style.background = `rgb(${col[0]},${col[1]},${col[2]})`;
      const st = f.grid[r][c];
      if (st === 1) div.textContent = "🐱";
      else if (st === 2) { const s = document.createElement("span"); s.className = "x"; s.textContent = "✕"; div.appendChild(s); }
      if (newCat.has(key(r, c))) div.classList.add("newcat");
      if (newExc.has(key(r, c))) div.classList.add("newexc");
      boardEl.appendChild(div);
    }
  }
  document.getElementById("counter").textContent =
    i === 0 ? "初始盘面" : `第 ${i} / ${frames.length - 1} 步`;
  document.getElementById("desc").textContent = f.desc;
  const marks = document.getElementById("marks");
  marks.innerHTML = "";
  for (const [r, c] of f.newCats) { const li = document.createElement("li"); li.className = "cat"; li.textContent = `猫 R${r + 1}C${c + 1}`; marks.appendChild(li); }
  for (const [r, c] of f.newExcluded) { const li = document.createElement("li"); li.className = "exc"; li.textContent = `排除 R${r + 1}C${c + 1}`; marks.appendChild(li); }
  document.getElementById("prev").disabled = i === 0;
  document.getElementById("next").disabled = i === frames.length - 1;
}

document.getElementById("prev").onclick = () => { if (i > 0) { i--; render(); } };
document.getElementById("next").onclick = () => { if (i < frames.length - 1) { i++; render(); } };
document.addEventListener("keydown", (e) => {
  if (e.key === "ArrowLeft" && i > 0) { i--; render(); }
  else if ((e.key === "ArrowRight" || e.key === " ") && i < frames.length - 1) { i++; render(); }
});
render();
</script>
</body>
</html>
"""


def to_html(title, size, region_ids, region_colors, init_grid, steps, status, mislabeled):
    def enc(grid):
        return [[_ENC[grid[r][c]] for c in range(size)] for r in range(size)]

    frames = [{
        "desc": "初始盘面：识别到的猫（🐱）与排除标记（✕）。猫为可信起点。",
        "grid": enc(init_grid),
        "newCats": [],
        "newExcluded": [],
    }]
    for s in steps:
        frames.append({
            "desc": s["desc"],
            "grid": enc(s["grid"]),
            "newCats": [[r, c] for k, r, c in s["marks"] if k == CAT],
            "newExcluded": [[r, c] for k, r, c in s["marks"] if k == EXCLUDED],
        })

    note = ""
    if mislabeled:
        cells = ", ".join(f"R{r+1}C{c+1}" for r, c in mislabeled)
        note = f"已纠正 {len(mislabeled)} 个错误排除标记（实为猫）：{cells}"

    data = {
        "size": size,
        "regionIds": region_ids,
        "regionColors": {str(k): list(v) for k, v in region_colors.items()},
        "frames": frames,
        "status": status,
        "title": title,
        "note": note,
    }
    import json as _json
    return HTML_TEMPLATE.replace("__DATA__", _json.dumps(data, ensure_ascii=False))


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("image", type=Path, help="Path to an in-progress level screenshot")
    parser.add_argument("--auto", action="store_true", help="Run all steps without pausing")
    parser.add_argument("--debug-image", type=Path, default=None, help="Write a parsed-board PNG (region ids + cell states)")
    parser.add_argument("--crop-image", type=Path, default=None, help="Write the isolated board crop for a quick visual check")
    parser.add_argument("--no-color", action="store_true", help="Plain ASCII board (no ANSI true-color background)")
    parser.add_argument("--html", type=Path, default=None, help="Write a self-contained interactive HTML report and exit")
    args = parser.parse_args()
    use_color = not args.no_color

    if not args.image.exists():
        print(f"error: {args.image} not found", file=sys.stderr)
        return 1

    im = Image.open(args.image).convert("RGB")
    size, region_ids, states, bounds, board, region_colors = parse_board(im)

    if args.crop_image:
        board.save(args.crop_image)
        print(f"Board crop written to {args.crop_image}", file=sys.stderr)

    if args.debug_image:
        render_debug(board, bounds, size, region_ids, states, args.debug_image)
        print(f"Debug image written to {args.debug_image}", file=sys.stderr)

    cats = [(r, c) for r in range(size) for c in range(size) if states[r][c] == CAT]
    excluded = [(r, c) for r in range(size) for c in range(size) if states[r][c] == EXCLUDED]
    region_count = len({rid for row in region_ids for rid in row})

    print(f"解析结果：{size}x{size}，{region_count} 个色块，"
          f"识别到 {len(cats)} 只猫、{len(excluded)} 个排除标记。")
    init_grid = [[UNKNOWN] * size for _ in range(size)]
    for (r, c) in cats:
        init_grid[r][c] = CAT
    for (r, c) in excluded:
        init_grid[r][c] = EXCLUDED
    if not args.html:
        print("图例：C=猫  x=排除  数字=未知格所属色块"
              + ("  （背景=色块原色；绿底=本步新增猫，红底=本步新增排除）" if use_color else "  （*=本步新增）"))
        print("初始盘面：")
        print(render_board(size, region_ids, init_grid, region_colors, set(), use_color))
        print()

    # -- certify unique solution, seeded with the trusted cats --------------
    forced_cats = {r: c for (r, c) in cats}
    solutions = solve_exact(size, region_ids, forced_cats, set(), limit=2)
    if not solutions:
        print("⚠️ 用识别到的猫求解无解：很可能是识图有误（色块或猫的位置）。"
              "请用 --debug-image 核对解析，修正后重试。", file=sys.stderr)
        return 2
    if len(solutions) > 1:
        print("⚠️ 当前信息下存在多个解：可能漏识了某些猫，或色块识别有误。"
              "请用 --debug-image 核对。", file=sys.stderr)
        return 2
    sol_cols = solutions[0]
    solution_set = {(r, sol_cols[r]) for r in range(size)}

    # -- validate / correct the excluded marks -----------------------------
    mislabeled = [(r, c) for (r, c) in excluded if (r, c) in solution_set]
    if mislabeled:
        print("❌ 发现错误的排除标记（这些格其实是猫，已纠正为未知）：")
        for (r, c) in mislabeled:
            print(f"   - R{r+1}C{c+1}")
        print()
    excluded = [cell for cell in excluded if cell not in solution_set]

    # -- run deduction once, then render to HTML or the terminal -----------
    deducer = Deducer(size, region_ids, cats, excluded, sol_cols)
    steps, status = run_deduction(deducer, size)

    if args.html:
        title = f"CatPuzzle 逐步求解 — {args.image.stem}"
        html = to_html(title, size, region_ids, region_colors, init_grid, steps, status, mislabeled)
        args.html.write_text(html, encoding="utf-8")
        print(f"HTML 已写入 {args.html}（用浏览器打开，← → 或按钮逐步查看，共 {len(steps)} 步，"
              f"{'已解出' if status == 'solved' else '中途需更高级技巧'}）")
        return 0

    print("开始逐步推理。每步给出依据与新增标注。"
          + ("（--auto：连续输出）\n" if args.auto else "（回车继续下一步，Ctrl-C 退出）\n"))
    for idx, s in enumerate(steps, 1):
        marks = s["marks"]
        new_cells = {(r, c) for _k, r, c in marks}
        cat_marks = [f"R{r+1}C{c+1}" for k, r, c in marks if k == CAT]
        exc_marks = [f"R{r+1}C{c+1}" for k, r, c in marks if k == EXCLUDED]
        print(f"步骤 {idx}：{s['desc']}")
        if cat_marks:
            print(f"   ✓ 新增猫：{', '.join(cat_marks)}")
        if exc_marks:
            print(f"   ✗ 新增排除：{', '.join(exc_marks)}")
        print(render_board(size, region_ids, s["grid"], region_colors, new_cells, use_color))
        if not args.auto:
            try:
                input()
            except (EOFError, KeyboardInterrupt):
                print("\n已退出。")
                return 0
        else:
            print()

    if status == "solved":
        print("🎉 已放满所有猫，推理完成。")
    else:
        last = steps[-1]["grid"] if steps else init_grid
        print("⏸ 当前技巧库（同行列色排除 / 唯一候选 / common attack / 锁定组 / "
              "强链 / 深度1试探反证）无法继续推进——这一步需要更深的嵌套假设。剩余盘面：")
        print(render_board(size, region_ids, last, region_colors, set(), use_color))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
