#!/usr/bin/env python3
"""Transcribe a *solved* CatPuzzle screenshot into LevelFixture solution data.

Companion to `transcribe_level.py` (see Docs/GeneratorDesignStudy.md for the
broader research workflow). Where that script reads an unsolved level and
emits `LevelDefinition`-shaped regionIDs, this one reads the "answer"
screenshot -- every cell is either an X mark (excluded), a cat face, or
occasionally left blank once the win condition is already met -- and emits
the planted solution as a list of cat positions, matching `LevelFixture`'s
`[CellPosition]` (one per row, in row order).

It also re-derives regionIDs from the still-visible background colors so the
solution can be cross-checked against the matching unsolved-screenshot
transcription, and runs the same row/column/region/adjacency uniqueness
checks `PuzzleValidator` would apply, purely as a transcription sanity check
(this script does not import CatPuzzleCore).

Cat glyphs cover almost an entire cell, so the background color sampled at a
cat cell is unreliable (confirmed against Docs/demo/233.PNG vs
233-answer.PNG: cell (6,0) reads as brown (168,109,74) under a cat glyph but
is actually orange (250,157,92) in the blank screenshot). Pass
--level-image pointing at the matching *unsolved* screenshot to source
regionIDs from there instead -- it has no overlays and is fully reliable.
Without it, region IDs at cat cells are reported as null rather than guessed.

Usage:
    python3 Scripts/transcribe_solution.py Docs/demo/233-answer.PNG --level-image Docs/demo/233.PNG
    python3 Scripts/transcribe_solution.py Docs/demo/233-answer.PNG --id demo-233 --swift
    python3 Scripts/transcribe_solution.py Docs/demo/233-answer.PNG --debug-image /tmp/233-answer-debug.png
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from transcribe_level import (
    BoardBounds,
    cell_rects,
    find_board_bounds,
    find_cell_boundaries,
    sample_cell,
    color_distance,
    transcribe as transcribe_blank_level,
)

REGION_MERGE_DISTANCE = 40.0

# Thresholds tuned against Docs/demo/233-answer.PNG: cat glyphs carry heavy
# black fur/eye-outline pixels; X marks are solid white strokes with no
# black; a cell left blank (win state reached before every cell was marked)
# has neither. Samples are restricted to the inner 70% of each cell to avoid
# the board's own rounded-corner background bleeding into edge cells.
CAT_BLACK_FRACTION = 0.05
EXCLUDED_WHITE_FRACTION = 0.15
INSET_MARGIN = 0.15


def classify_cell(im: Image.Image, rect: tuple[int, int, int, int]) -> str:
    px = im.load()
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    ix0, iy0 = x0 + int(w * INSET_MARGIN), y0 + int(h * INSET_MARGIN)
    ix1, iy1 = x1 - int(w * INSET_MARGIN), y1 - int(h * INSET_MARGIN)

    black = white = total = 0
    for y in range(iy0, iy1, 2):
        for x in range(ix0, ix1, 2):
            r, g, b = px[x, y]
            total += 1
            if r < 60 and g < 60 and b < 60:
                black += 1
            if r > 235 and g > 235 and b > 235:
                white += 1
    total = max(1, total)

    if black / total > CAT_BLACK_FRACTION:
        return "cat"
    if white / total > EXCLUDED_WHITE_FRACTION:
        return "excluded"
    return "empty"


def transcribe_solution(im: Image.Image):
    bounds = find_board_bounds(im)
    x_bounds = find_cell_boundaries(im, bounds, axis="x")
    y_bounds = find_cell_boundaries(im, bounds, axis="y")
    cols, rows = len(x_bounds) - 1, len(y_bounds) - 1
    if rows != cols:
        raise ValueError(f"Detected non-square grid ({rows} rows x {cols} cols); check the screenshot crop.")

    rects = cell_rects(x_bounds, y_bounds)

    states = [[classify_cell(im, rects[r][c]) for c in range(cols)] for r in range(rows)]

    # Cat glyphs cover almost the whole cell, so their corner samples are not
    # trustworthy region-color evidence (see module docstring). Cluster only
    # over non-cat cells and leave cat cells as -1 ("unknown") here; main()
    # fills them in from a companion blank-level transcription when given.
    region_ids: list[list[int]] = [[-1] * cols for _ in range(rows)]
    region_colors: dict[int, tuple[int, int, int]] = {}
    for r in range(rows):
        for c in range(cols):
            if states[r][c] == "cat":
                continue
            color, _variance = sample_cell(im, rects[r][c])
            match = None
            for region_id, known_color in region_colors.items():
                if color_distance(color, known_color) <= REGION_MERGE_DISTANCE:
                    match = region_id
                    break
            if match is None:
                match = len(region_colors)
                region_colors[match] = color
            region_ids[r][c] = match

    return bounds, rows, states, region_ids, region_colors


def validate_solution(size: int, cats: list[tuple[int, int]], region_ids: list[list[int]]) -> dict:
    rows_used = [r for r, _c in cats]
    cols_used = [c for _r, c in cats]
    regions_used = [region_ids[r][c] for r, c in cats]
    regions_known = all(region_id != -1 for region_id in regions_used)

    def all_unique(values: list[int], expected: int) -> bool:
        return len(values) == expected and len(set(values)) == expected

    adjacency_ok = True
    cat_set = set(cats)
    for r, c in cats:
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if dr == 0 and dc == 0:
                    continue
                if (r + dr, c + dc) in cat_set:
                    adjacency_ok = False

    return {
        "catCount": len(cats),
        "expectedCatCount": size,
        "rowsUnique": all_unique(rows_used, size),
        "columnsUnique": all_unique(cols_used, size),
        "regionsUnique": all_unique(regions_used, size) if regions_known else None,
        "noAdjacentCats": adjacency_ok,
    }


def render_debug_image(im: Image.Image, bounds: BoardBounds, size: int, states: list[list[str]], out_path: Path) -> None:
    annotated = im.convert("RGB").copy()
    draw = ImageDraw.Draw(annotated)
    cell_w = (bounds.x1 - bounds.x0) / size
    cell_h = (bounds.y1 - bounds.y0) / size
    colors = {"cat": (0, 90, 255), "excluded": (0, 170, 0), "empty": (200, 0, 0)}
    for r in range(size):
        for c in range(size):
            x0 = bounds.x0 + int(c * cell_w)
            y0 = bounds.y0 + int(r * cell_h)
            x1 = bounds.x0 + int((c + 1) * cell_w)
            y1 = bounds.y0 + int((r + 1) * cell_h)
            draw.rectangle([x0, y0, x1, y1], outline=colors[states[r][c]], width=3)
    annotated.save(out_path)


def to_swift_snippet(level_id: str, size: int, cats: list[tuple[int, int]]) -> str:
    positions = ",\n".join(f"        CellPosition(row: {r}, column: {c})" for r, c in cats)
    return f"""// Transcribed by Scripts/transcribe_solution.py from a solved-level screenshot
// solution for "{level_id}" ({size}x{size})
solution: [
{positions},
]"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", type=Path, help="Path to a solved-level screenshot (e.g. Docs/demo/233-answer.PNG)")
    parser.add_argument("--id", dest="level_id", default=None, help="Level id to embed in the output (default: file stem)")
    parser.add_argument("--swift", action="store_true", help="Also print a Swift solution snippet")
    parser.add_argument("--debug-image", type=Path, default=None, help="Write an annotated PNG showing detected cell states")
    parser.add_argument(
        "--level-image", type=Path, default=None,
        help="Path to the matching *unsolved* screenshot; sources regionIDs from there instead of the "
             "solved image, since cat glyphs make region color at cat cells unreliable (see module docstring)",
    )
    args = parser.parse_args()

    if not args.image.exists():
        print(f"error: {args.image} not found", file=sys.stderr)
        return 1

    im = Image.open(args.image).convert("RGB")
    bounds, size, states, region_ids, region_colors = transcribe_solution(im)
    region_source = "self-derived (cat cells unresolved, -1)"

    if args.level_image:
        if not args.level_image.exists():
            print(f"error: {args.level_image} not found", file=sys.stderr)
            return 1
        blank_im = Image.open(args.level_image).convert("RGB")
        blank_level = transcribe_blank_level(blank_im)
        if blank_level.size != size:
            print(
                f"error: {args.level_image} is {blank_level.size}x{blank_level.size}, "
                f"but {args.image} is {size}x{size}",
                file=sys.stderr,
            )
            return 1
        region_ids = blank_level.region_ids
        region_colors = blank_level.region_colors
        region_source = f"companion unsolved screenshot ({args.level_image.name})"

    cats: list[tuple[int, int]] = []
    ambiguous: list[dict] = []
    for r in range(size):
        row_cats = [c for c in range(size) if states[r][c] == "cat"]
        if len(row_cats) == 1:
            cats.append((r, row_cats[0]))
        elif len(row_cats) == 0:
            # A cell can be left unmarked once the win condition is already
            # met; if exactly one cell in the row is unclassified ("empty"),
            # treat it as the row's cat by elimination.
            empty_cells = [c for c in range(size) if states[r][c] == "empty"]
            if len(empty_cells) == 1:
                cats.append((r, empty_cells[0]))
                states[r][empty_cells[0]] = "cat"
            else:
                ambiguous.append({"row": r, "reason": "no cat and not exactly one empty cell", "emptyColumns": empty_cells})
        else:
            ambiguous.append({"row": r, "reason": "multiple cat glyphs detected", "columns": row_cats})

    level_id = args.level_id or args.image.stem
    payload = {
        "id": level_id,
        "size": size,
        "catCount": len(cats),
        "solution": [{"row": r, "column": c} for r, c in sorted(cats)],
        "regionIDs": region_ids,
        "regionIDSource": region_source,
        "regionColorLegend": {str(k): list(v) for k, v in sorted(region_colors.items())},
        "ambiguousRows": ambiguous,
        "validation": validate_solution(size, cats, region_ids),
    }
    print(json.dumps(payload, indent=2))

    if args.swift:
        print()
        print(to_swift_snippet(level_id, size, sorted(cats)))

    if args.debug_image:
        render_debug_image(im, bounds, size, states, args.debug_image)
        print(f"\nDebug image written to {args.debug_image}", file=sys.stderr)

    if ambiguous:
        print(f"\nWarning: {len(ambiguous)} row(s) could not be resolved to exactly one cat; see 'ambiguousRows'.", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
