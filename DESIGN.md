# CatPuzzle Design Guidelines

## Design Direction

CatPuzzle should feel bright, clear, friendly, and calm. The board is always the visual focus; decoration supports comprehension rather than competing with it. The supplied prototype is a reference for its warm background, vivid color blocks, rounded surfaces, and obvious game states—not a source for copied artwork, layout, branding, or features.

Core principles:

1. **Board first:** the puzzle receives the largest continuous area of the screen.
2. **Readable at a glance:** cats, exclusions, mistakes, and available actions must be immediately distinguishable.
3. **Playful restraint:** use rounded shapes and cheerful color without excessive gradients, shadows, animation, or ornament.
4. **Original identity:** use CatPuzzle-owned icons, copy, illustrations, and level data.

## Color System

Use semantic tokens rather than colors embedded directly in views.

| Token | Light value | Purpose |
| --- | --- | --- |
| `background` | `#FFF9F3` | Warm app background |
| `surface` | `#FFFFFF` | Cards, overlays, controls |
| `textPrimary` | `#49353F` | Primary labels and icons |
| `textSecondary` | `#806C75` | Instructions and metadata |
| `action` | `#20B96B` | Start, Continue, primary action |
| `warning` | `#FF704F` | Illegal placement and mistakes |
| `divider` | `#E9DED7` | Quiet separators and cell grid |

The six board Regions use clear mid-value colors: pink `#ED86D5`, green `#38AA70`, yellow `#F4CF68`, blue `#5D83B4`, brown `#AE7654`, and lime `#89CF78`. Keep fills at full or near-full opacity; washed-out colors make the rules harder to read. Every Region must also have a subtle visual symbol and an accessibility label because color alone cannot distinguish Regions for all players.

## Tutorial (Dark) Color System

The tutorial is the one screen exempted from the app's forced-light lock: it
runs full-bleed dark with per-cell spotlight cutouts, closer to the onboarding
style of the reference competitor recordings than to `GameScreen`. Its tokens
live in `TutorialTheme`, a separate namespace from the table above — a call
site should make clear which screen a color belongs to.

| Token | Dark value | Purpose |
| --- | --- | --- |
| `background` | near-black | Full-bleed tutorial background |
| `scrim` | `black` at ~25% opacity | Keep earlier crosses visible outside the current focus |
| `surface` | dark elevated gray | The step caption card |
| `textPrimary` | `white` | Primary labels |
| `textSecondary` | `white` at ~62% opacity | Explanation copy |
| `accent` | `#20B96B` (`CatPuzzleTheme.action`) | Reused for continuity — the same color the player meets on every ladder level |
| `spotlightRing` | `white` at ~90% opacity | Emphasis strokes over spotlighted cells |
| `celebration` | warm gold | The graduation page's checkmark |

The board keeps its Region colors and marker shapes. During guided steps,
cells outside the focus are lightly shaded and cannot be edited; earlier
crosses stay readable as the player moves from row to column to corners.

## Typography & Shape

Use San Francisco Rounded where available and support Dynamic Type. Prefer `.largeTitle` for the product or completion state, `.title2` for level identity, `.headline` for status, and `.body`/`.footnote` for guidance. Body text must remain at least 17 pt at the default size.

Cards and buttons use 14–20 pt corner radii. Board cells use 6–8 pt radii with 3–4 pt gaps. Use soft shadows only to separate floating surfaces; never place shadows between individual cells.

## Game Screen Layout

Order content vertically:

1. Compact header with level name and mistake status.
2. Optional concise rule reminder; it must not displace the board on smaller screens. A tutorial step's own explanation is a floating callout anchored to the cells it is teaching (with a pointer toward them) rather than inline text, so its length can vary step to step without ever shifting the board or the controls below it.
3. Centered square 6×6 board using the maximum available width.
4. Feedback message with reserved height to prevent layout jumps.
5. Undo and Restart controls in the safe area.

Do not add score, timer, advertisements, power-ups, or a level list unless product requirements change.

## Formal Game Visual Details

The level-start screen shows the real App Icon artwork in the upper-middle area
and one prominent action near the bottom. The action uses the upcoming level's
localized title; tutorial entry retains its localized Start Tutorial label.
Settings remains at the top right. Do not add a separate level heading, next-level
caption, puzzle-size description, or play icon. AppLogo mirrors the AppIcon artwork.

The formal game uses a single quiet rule strip with miniature board diagrams
and secondary text. Preserve the diagrams' paw and exclusion marks so each rule
remains visually meaningful. Use the muted theme colors in the formal game;
excluded marks use white crosses on muted tiles, and cats reuse the board's circular paw marker.
The tutorial retains its existing diagram colors. Keep the three rules visible,
place the text to the right of each fixed-size diagram, and keep the strip compact.
Text may shrink to fit up to three lines while diagrams retain priority. Stack the rules
and allow full text wrapping at accessibility text sizes.

Lives use flat cat faces; completed Regions use filled paws and unfinished
Regions use outlined paws. Game actions, hint actions, and outcome actions share
16 pt rounded buttons, with a white secondary surface and dark green primary
surface (`actionInk`) for legible white text. Life faces use `lifeAccent`.
Place the text-only Hint action directly below the board with the same 14 pt
spacing used between the rule strip and board. Let the stack follow the board's
actual size; hint details and feedback appear below the actions.
Formal boards use 4 pt screen margins, 2 pt inner padding, cell gaps equal to
8% of cell width (rounded to device pixels), and 4 pt cell corners.
Compute the unrounded cell width as available inner width / (N + 0.08 × (N − 1)),
then derive the gap and distribute the remaining width equally among cells.
Rendering and gesture hit testing share these dimensions.
The board expands with available width; other controls keep
their 16 pt screen margins. Tutorial boards retain their existing geometry.
Cell marks scale with the cell without fixed font-size caps: the paw uses a
60% font size and 8% inset, and the rounded multiplication sign uses a 115%
font size, with optical centering and visible space around both marks.

Hint previews shade only the rounded cell interior at 24% using `textPrimary`.
A 3 pt dark inset outline identifies result cells even on green Regions; keep
the surrounding Region colors readable. Failure retains the quiet outcome card.
Success keeps the solved board under a dark scrim. An original orange mascot
jumps with open arms, catches a paw medal, and hugs it while swaying its tail.
Warm localized rays and three confetti bursts frame the character. The 252
particles and character animation settle after seven seconds. At 2.1 seconds,
show a CTA with the upcoming level's localized title; it starts that level directly
without the preparation screen. The last level loops to Level 1. Standalone
playtests retain their Continue action. Reduced Motion immediately shows the
settled mascot and CTA. Hide the underlying board from touch and accessibility
while an outcome is presented. Celebration copy ships in both app languages.

## Cell States & Interaction

- **Empty:** vivid Region fill with no central mark.
- **Excluded:** large high-contrast `×`, visually centered and readable without relying on opacity.
- **Cat:** a single original cat/paw mark with strong separation from the Region fill.
- **Illegal placement:** keep the cell unchanged; show brief warning feedback and update the mistake count.
- **Given (locked):** a level may ship with a cell already marked excluded or containing a cat. Render its normal excluded/cat marker plus a small `lock.fill` glyph in the opposite corner from the Region icon. It never responds to tap, drag, or the cat-toggle accessibility action, and Restart returns it to its given value rather than clearing it.

Single-tap feedback must appear immediately. A same-cell second tap within the app’s double-tap interval resolves to one cat operation, without leaving an exclusion or creating an extra Undo entry. Provide explicit accessibility actions for marking excluded and toggling a cat. Interactive targets must be at least 44×44 pt.

Dragging from an empty cell continuously marks cells as excluded. Dragging from an excluded cell continuously clears exclusions. The starting cell fixes the mode for the entire gesture, and neither mode changes cells containing cats.

## Motion & Accessibility

Use 120–200 ms ease-out transitions for marks and overlays. Completion may use one restrained scale/fade animation. Respect Reduce Motion and avoid continuous animation. Maintain WCAG AA text contrast, never communicate status with color alone, and give every cell a row, column, Region, and state accessibility description.

## Review Checklist

- The board remains legible at the smallest supported iPhone size.
- All six Regions, cell states, and primary actions are distinguishable.
- Dynamic Type and VoiceOver do not hide game state or controls.
- Visible UI changes include light-mode screenshots in the pull request.
- New visuals remain original and consistent with these semantic tokens.
