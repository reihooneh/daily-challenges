# How Anchorwise works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 anchor.txt ──▶ parse.lua      fixed line forms, ranges → anchor (pieces, load direction, rigging)
                    │
                    ▼
               analyse.lua     with every piece holding, then with each piece removed in turn
                 │      │
          fixed.lua    sliding.lua
     springs + Newton   equal tension: the lowest point on the "sling length" curve
                 │      │
                    ▼
               report.lua      loads, shares, spread angle, drops, jolts, warnings
```

## 2. File tour

| File | Job |
|---|---|
| `anchorwise.lua` | Bounded reading, exit codes, `run()` for the tests |
| `anchorwise/parse.lua` | The file format and material stretch figures |
| `anchorwise/vec.lua` | 2D vector helpers and a 2×2 solver |
| `anchorwise/fixed.lua` | Arms as springs; Newton's method for where the master point settles |
| `anchorwise/sliding.lua` | Equal tension; the lowest point the sling allows |
| `anchorwise/analyse.lua` | Intact and failure cases, and the jolt estimate |
| `anchorwise/report.lua` | The printed check and its warnings |
| `test/test_anchorwise.lua` | 64 checks under a strict-globals guard |

## 3. Key ideas

### Statics: the master point is in balance
Each arm pulls the master point towards its piece. The load pulls it down, or off to one side. At rest the vector sum is zero. Two equal arms at angle θ apart each carry `W / (2 cos(θ/2))`: about half the load at small angles, the whole load at 120°, and more beyond. That's why the report shows the spread angle.

### Fixed rigging: springs
Once tied, each arm has a fixed rest length ℓ (plus any slack from imperfect tying). A sling stretches in proportion to force, so the arm acts as a spring of stiffness `EA/ℓ`, where EA describes the material: nylon stretches about four times as much as Dyneema. A slack arm carries nothing. Under load the master point moves to the point where the spring forces balance the load. Finding it means solving two non-linear equations (x and y), done with **Newton's method**: a numerical 2×2 Jacobian, with steps limited and halved until the leftover force shrinks.

### Sliding rigging: equal tension, lowest point
A sling running freely through every piece has the same tension in every arm. The master point slides to where the load can pull it furthest. Formally, it maximises `load direction · position` subject to `Σ |M − Pᵢ| = sling length`. That constraint traces a smooth convex curve (an ellipse for two pieces). Anchorwise walks round it: for each direction from the centre of the pieces, bisection finds where the arms add up to the sling length. A scan plus golden-section search then finds the furthest point. There, the arm directions add up to point straight back against the load, so `T = W / |Σ arm directions|`.

### When a piece fails: drop and jolt
Removing a piece and solving again gives the new rest position. How far it moved along the load is the **drop**. For sliding rigging a limiter knot caps the drop. Treating the load as falling freely through that drop onto a spring of stiffness k gives an upper estimate of the jolt:

```
peak = W (1 + √(1 + 2 k h / W))
```

Even a drop of almost nothing doubles the load (a weight suddenly released onto a slack system). A stiff Dyneema sling and a 15 cm drop can multiply it five times. This is the trade-off between sliding systems (even sharing, but extension) and fixed ones (little extension, uneven sharing).

### Lua features you met here
- **Modules as tables** returned from files, loaded with `require` and a `package.path` set relative to the script.
- **Errors as tables** (`error({input = ...}, 0)`) to tell input problems from bugs, caught with `pcall`.
- **Patterns, not regular expressions:** byte classes like `[\0-\8\11-\31\127]` and UTF-8 byte sequences for hidden direction marks.
- **`utf8.len`** to reject invalid UTF-8.
- **Metatables on `_G`** in the tests, to make any undeclared global an error.

## 4. Interview questions you might get

**Q: Why does a cordelette often load one piece much more than the others?**
A: Because tied-off arms act like springs. A shorter arm, or one pulling more directly along the load, is effectively stiffer. An arm tied a few millimetres long only comes tight after the others have stretched. The model solves the spring network exactly, and the test with 3 mm of slack shows that arm taking less than its share.

**Q: How do you find where a sliding sling settles?**
A: Equal tension in every arm means the master point sits at the lowest point, along the load direction, of the curve where the arm lengths add up to the sling length. The curve is convex, so I search over directions from the pieces' centre, bisect along each ray to land on the curve, then refine the best direction with golden-section search. The test checks a two-piece case against the closed-form answer: depth √(arm² − half-span²).

**Q: Why is extension dangerous even with a good piece left?**
A: The load falls through the extension before the system catches it, and the energy has to be absorbed by stretching a fairly stiff sling. With mass-spring energy balance the peak is `W(1 + √(1 + 2kh/W))`. A longer drop or a stiffer sling means a bigger jolt, which is why limiter knots and short arms matter.

## 5. Ideas to extend it

1. **3D:** pieces in a corner or on a slab need the third dimension; the same equations extend with 3×3 solves.
2. **Friction:** real sliding X systems don't equalise perfectly because of carabiner friction; model a friction coefficient at each piece.
3. **Draw it:** an SVG sketch of the pieces, arms and master point, coloured by load.
