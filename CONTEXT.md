# CatPuzzle Domain

CatPuzzle is a spatial logic puzzle in which cats must satisfy row, column, region, and non-touching constraints. Region geometry also shapes the visual clarity and reasoning experience of a level.

## Language

**Region**:
A group of cells that must contain exactly one cat. A region may be rendered with a color, but color is presentation rather than the rule-bearing concept.
_Avoid_: Color, color group

**Connected Region**:
A region whose cells form one component under eight-neighbor adjacency, including horizontal, vertical, and diagonal contact. Connectivity is a level-design quality, not a universal validity requirement.
_Avoid_: Continuous color

**Mainline Level**:
A level with one solution that can be completed through deterministic, explainable deductions without assumptions.
_Avoid_: Normal level

**Challenge Level**:
A level whose intended reasoning may use a bounded, explainable assumption and contradiction.
_Avoid_: Hard level

**Human-Designed Sample**:
A level layout supplied as a design screenshot and used to identify reusable geometric and reasoning characteristics. It is research input, not content to copy into the game.
_Avoid_: Training level

**Region Geometry Profile**:
A named family of region layouts with characteristic area balance, shape, and spatial relationships. Profiles describe level-design style rather than visual color assignment.
_Avoid_: Color strategy

**Deduction Blueprint**:
The intended techniques and partial dependency order of explainable deductions that a generated Mainline Level is constructed to expose. It records milestones rather than one exact solver execution order.
_Avoid_: Solver trace, random difficulty

**Logical Anchor**:
The first deduction deliberately made available to start a level's intended reasoning chain.
_Avoid_: Free cat, giveaway
