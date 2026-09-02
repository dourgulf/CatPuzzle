#!/usr/bin/env python3
"""Transcribe a hand-designed CatPuzzle level screenshot into LevelDefinition data.

Research tool only (see Docs/GeneratorDesignStudy.md): the source screenshots
in Docs/demo are local design input, not product levels or checked-in assets.
This script reads one such screenshot, locates the N x N region grid by pixel
color, clusters cell colors into region IDs, and emits the level in the same
shape as `LevelDefinition` (id, size, catCount, maxMistakes, regionIDs), plus
any hint-cat cell it noticed so a human reviewer can cross-check the result.

It does NOT compute a solution or run the logical/exact solver -- feed the
output regionIDs into PuzzleSolver / LogicalPuzzleSolver (Swift side) for
uniqueness certification and technique analysis, matching the existing
GeneratorDesignStudy.md workflow.

Usage:
    python3 Scripts/transcribe_level.py Docs/demo/232.PNG
    python3 Scripts/transcribe_level.py Docs/demo/232.PNG --id demo-232 --swift
    python3 Scripts/transcribe_level.py Docs/demo/232.PNG --debug-image /tmp/232-annotated.png
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw

# Backdrop colors observed in the source screenshots: the page background and
# the white card / grid-line gaps. Any pixel close to either is "not a cell".
BACKGROUND_SAMPLES = [(247, 242, 239), (255, 255, 255)]
BACKGROUND_TOLERANCE = 10

# Fraction of a scanline that must be "colorful" for it to count as part of
# the board rather than a small rule-icon thumbnail or header text.
BOARD_FRACTION_THRESHOLD = 0.6

# Two sampled cell colors within this Euclidean RGB distance are the same region.
REGION_MERGE_DISTANCE = 40.0

# A cell whose 5 sample points disagree by more than this is probably covered
# by a cat glyph rather than being flat region color.
CAT_OVERLAY_VARIANCE = 45.0


def is_background(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    for br, bg, bb in BACKGROUND_SAMPLES:
        if abs(r - br) <= BACKGROUND_TOLERANCE and abs(g - bg) <= BACKGROUND_TOLERANCE and abs(b - bb) <= BACKGROUND_TOLERANCE:
            return True
    return False


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def longest_run(flags: list[bool], max_gap: int = 0) -> tuple[int, int]:
    """Return (start, end) inclusive indices of the longest run of True.

    `max_gap` tolerates short False stretches inside a run (e.g. the thin
    grid-line gaps between cells), so the board's overall extent is not cut
    short at every internal separator -- only at real background margins.
    """
    runs: list[tuple[int, int]] = []
    start = None
    for i, flag in enumerate(flags + [False]):
        if flag and start is None:
            start = i
        elif not flag and start is not None:
            runs.append((start, i - 1))
            start = None

    if not runs:
        return (0, -1)

    merged = [runs[0]]
    for run_start, run_end in runs[1:]:
        prev_start, prev_end = merged[-1]
        if run_start - prev_end - 1 <= max_gap:
            merged[-1] = (prev_start, run_end)
        else:
            merged.append((run_start, run_end))

    return max(merged, key=lambda run: run[1] - run[0])


@dataclass
class BoardBounds:
    x0: int
    x1: int
    y0: int
    y1: int


def find_board_bounds(im: Image.Image, step: int = 3, max_gap_px: int = 40) -> BoardBounds:
    w, h = im.size
    px = im.load()
    max_gap_idx = max_gap_px // step + 1

    ys = list(range(0, h, step))
    row_frac = []
    for y in ys:
        colorful = sum(1 for x in range(0, w, step) if not is_background(px[x, y]))
        row_frac.append(colorful / len(range(0, w, step)))
    y_start_idx, y_end_idx = longest_run([f > BOARD_FRACTION_THRESHOLD for f in row_frac], max_gap=max_gap_idx)
    if y_end_idx < y_start_idx:
        raise ValueError("Could not find a board-like region (rows); adjust thresholds.")
    y0, y1 = ys[y_start_idx], ys[y_end_idx]

    xs = list(range(0, w, step))
    y_range = range(y0, y1 + 1, step)
    col_frac = []
    for x in xs:
        colorful = sum(1 for y in y_range if not is_background(px[x, y]))
        col_frac.append(colorful / max(1, len(list(y_range))))
    x_start_idx, x_end_idx = longest_run([f > BOARD_FRACTION_THRESHOLD for f in col_frac], max_gap=max_gap_idx)
    if x_end_idx < x_start_idx:
        raise ValueError("Could not find a board-like region (columns); adjust thresholds.")
    x0, x1 = xs[x_start_idx], xs[x_end_idx]

    return BoardBounds(x0=x0, x1=x1, y0=y0, y1=y1)


def find_cell_boundaries(im: Image.Image, bounds: BoardBounds, axis: str, step: int = 2) -> list[int]:
    """Find the pixel offsets of grid-line gaps along one axis inside bounds.

    Returns the boundary positions (including the two outer edges) so that
    consecutive pairs delimit one row or one column of cells.
    """
    px = im.load()
    if axis == "x":
        positions = range(bounds.x0, bounds.x1 + 1, step)
        cross = range(bounds.y0, bounds.y1 + 1, step)
        sample = lambda p, c: px[p, c]
    else:
        positions = range(bounds.y0, bounds.y1 + 1, step)
        cross = range(bounds.x0, bounds.x1 + 1, step)
        sample = lambda p, c: px[c, p]

    frac = []
    for p in positions:
        colorful = sum(1 for c in cross if not is_background(sample(p, c)))
        frac.append(colorful / max(1, len(list(cross))))

    is_gap = [f < 0.15 for f in frac]
    positions = list(positions)

    boundaries = [positions[0]]
    i = 0
    n = len(positions)
    while i < n:
        if is_gap[i]:
            j = i
            while j < n and is_gap[j]:
                j += 1
            mid = positions[(i + j - 1) // 2]
            if mid - boundaries[-1] > 5:
                boundaries.append(mid)
            i = j
        else:
            i += 1
    if boundaries[-1] != positions[-1]:
        boundaries.append(positions[-1])
    return boundaries


def cell_rects(x_bounds: list[int], y_bounds: list[int]) -> list[list[tuple[int, int, int, int]]]:
    rows = len(y_bounds) - 1
    cols = len(x_bounds) - 1
    rects = []
    for r in range(rows):
        row_rects = []
        for c in range(cols):
            row_rects.append((x_bounds[c], y_bounds[r], x_bounds[c + 1], y_bounds[r + 1]))
        rects.append(row_rects)
    return rects


def sample_cell(im: Image.Image, rect: tuple[int, int, int, int]) -> tuple[tuple[int, int, int], float]:
    """Return (representative_color, sample_variance) for one cell.

    Samples five points -- center and four inset corners -- because a cat
    glyph is drawn centered but usually doesn't cover a cell's corners.
    """
    px = im.load()
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    points = [
        (x0 + w // 2, y0 + h // 2),
        (x0 + int(w * 0.22), y0 + int(h * 0.22)),
        (x0 + int(w * 0.78), y0 + int(h * 0.22)),
        (x0 + int(w * 0.22), y0 + int(h * 0.78)),
        (x0 + int(w * 0.78), y0 + int(h * 0.78)),
    ]
    colors = [px[px_x, px_y] for px_x, px_y in points]

    # Corner samples are more reliable than the center for the underlying
    # region color; use their most common (rounded) value as the representative.
    corner_colors = colors[1:]
    buckets: dict[tuple[int, int, int], list[tuple[int, int, int]]] = {}
    for c in corner_colors:
        key = tuple(v // 8 * 8 for v in c)
        buckets.setdefault(key, []).append(c)
    best_bucket = max(buckets.values(), key=len)
    representative = tuple(sum(v[i] for v in best_bucket) // len(best_bucket) for i in range(3))

    variance = max(color_distance(representative, c) for c in colors)
    return representative, variance


@dataclass
class TranscribedLevel:
    size: int
    region_ids: list[list[int]]
    region_colors: dict[int, tuple[int, int, int]]
    suspected_cats: list[dict]


def transcribe(im: Image.Image) -> TranscribedLevel:
    bounds = find_board_bounds(im)
    x_bounds = find_cell_boundaries(im, bounds, axis="x")
    y_bounds = find_cell_boundaries(im, bounds, axis="y")

    cols = len(x_bounds) - 1
    rows = len(y_bounds) - 1
    if rows != cols:
        raise ValueError(f"Detected non-square grid ({rows} rows x {cols} cols); check the screenshot crop.")

    rects = cell_rects(x_bounds, y_bounds)

    region_ids: list[list[int]] = [[0] * cols for _ in range(rows)]
    region_colors: dict[int, tuple[int, int, int]] = {}
    suspected_cats: list[dict] = []

    for r in range(rows):
        for c in range(cols):
            color, variance = sample_cell(im, rects[r][c])
            match = None
            for region_id, known_color in region_colors.items():
                if color_distance(color, known_color) <= REGION_MERGE_DISTANCE:
                    match = region_id
                    break
            if match is None:
                match = len(region_colors)
                region_colors[match] = color
            region_ids[r][c] = match
            if variance > CAT_OVERLAY_VARIANCE:
                suspected_cats.append({"row": r, "column": c, "sampleVariance": round(variance, 1)})

    return TranscribedLevel(size=rows, region_ids=region_ids, region_colors=region_colors, suspected_cats=suspected_cats)


def render_debug_image(im: Image.Image, level: TranscribedLevel, bounds: BoardBounds, out_path: Path) -> None:
    annotated = im.convert("RGB").copy()
    draw = ImageDraw.Draw(annotated)
    size = level.size
    cell_w = (bounds.x1 - bounds.x0) / size
    cell_h = (bounds.y1 - bounds.y0) / size
    for r in range(size):
        for c in range(size):
            cx = bounds.x0 + int((c + 0.5) * cell_w)
            cy = bounds.y0 + int((r + 0.5) * cell_h)
            label = str(level.region_ids[r][c])
            draw.rectangle(
                [bounds.x0 + int(c * cell_w), bounds.y0 + int(r * cell_h),
                 bounds.x0 + int((c + 1) * cell_w), bounds.y0 + int((r + 1) * cell_h)],
                outline=(255, 0, 0),
            )
            draw.text((cx - 5, cy - 6), label, fill=(255, 0, 0))
    for cat in level.suspected_cats:
        cx = bounds.x0 + int((cat["column"] + 0.5) * cell_w)
        cy = bounds.y0 + int((cat["row"] + 0.5) * cell_h)
        draw.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], outline=(0, 0, 255), width=3)
    annotated.save(out_path)


def to_level_definition_json(level: TranscribedLevel, level_id: str, max_mistakes: int) -> dict:
    return {
        "id": level_id,
        "size": level.size,
        "catCount": level.size,
        "maxMistakes": max_mistakes,
        "regionIDs": level.region_ids,
        "regionCount": len(level.region_colors),
        "suspectedCats": level.suspected_cats,
        "regionColorLegend": {
            str(region_id): list(color) for region_id, color in sorted(level.region_colors.items())
        },
    }


def to_swift_snippet(level: TranscribedLevel, level_id: str, max_mistakes: int) -> str:
    rows_text = ",\n".join(
        "                [" + ", ".join(str(v) for v in row) + "]" for row in level.region_ids
    )
    cats_comment = ", ".join(f"({c['row']},{c['column']})" for c in level.suspected_cats) or "none detected"
    return f"""// Transcribed by Scripts/transcribe_level.py -- verify with PuzzleSolver / LogicalPuzzleSolver
// before promoting to a product fixture. Suspected hint-cat cells (row, column): {cats_comment}
LevelDefinition(
    id: "{level_id}",
    size: {level.size},
    catCount: {level.size},
    maxMistakes: {max_mistakes},
    regionIDs: [
{rows_text},
    ]
)"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", type=Path, help="Path to a level screenshot (e.g. Docs/demo/232.PNG)")
    parser.add_argument("--id", dest="level_id", default=None, help="Level id to embed in the output (default: file stem)")
    parser.add_argument("--max-mistakes", type=int, default=3, help="Placeholder maxMistakes; not derivable from the screenshot (default: 3)")
    parser.add_argument("--swift", action="store_true", help="Also print a Swift LevelDefinition snippet")
    parser.add_argument("--debug-image", type=Path, default=None, help="Write an annotated PNG showing detected region IDs and grid lines")
    args = parser.parse_args()

    if not args.image.exists():
        print(f"error: {args.image} not found", file=sys.stderr)
        return 1

    im = Image.open(args.image).convert("RGB")
    bounds = find_board_bounds(im)
    level = transcribe(im)

    level_id = args.level_id or args.image.stem
    payload = to_level_definition_json(level, level_id, args.max_mistakes)
    print(json.dumps(payload, indent=2))

    if args.swift:
        print()
        print(to_swift_snippet(level, level_id, args.max_mistakes))

    if args.debug_image:
        render_debug_image(im, level, bounds, args.debug_image)
        print(f"\nDebug image written to {args.debug_image}", file=sys.stderr)

    if level.suspected_cats:
        print(f"\nNote: {len(level.suspected_cats)} cell(s) look like they have a cat/hint glyph drawn over them; "
              "cross-check row/column against the screenshot -- LevelDefinition itself carries no cat data.",
              file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
