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

## Typography & Shape

Use San Francisco Rounded where available and support Dynamic Type. Prefer `.largeTitle` for the product or completion state, `.title2` for level identity, `.headline` for status, and `.body`/`.footnote` for guidance. Body text must remain at least 17 pt at the default size.

Cards and buttons use 14–20 pt corner radii. Board cells use 6–8 pt radii with 3–4 pt gaps. Use soft shadows only to separate floating surfaces; never place shadows between individual cells.

## Game Screen Layout

Order content vertically:

1. Compact header with level name and mistake status.
2. Optional concise rule reminder; it must not displace the board on smaller screens.
3. Centered square 6×6 board using the maximum available width.
4. Feedback message with reserved height to prevent layout jumps.
5. Undo and Restart controls in the safe area.

Do not add score, timer, advertisements, power-ups, or a level list unless product requirements change.

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
