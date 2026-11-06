# How Tubewise works

A neon sign is a drawing made of one glowing line, or as few as possible. Tubewise turns that craft problem into the route inspection problem from graph theory, solves it, and hands the bender a plan.

## 1. The big picture

```
text ──layout──▶ strokes (mm) ──build──▶ graph: nodes where strokes end, bend, cross or touch
                                                 edges = straight pieces of lit glass
                                                  │
              join separate pieces with jumpers (minimum spanning tree, never across lit glass)
                                                  │
              odd-degree nodes ── shortest black connections (Dijkstra) ── minimum-weight matching
                                                  │                          (two free ends)
                              add the matched connections as black glass
                                                  │
                      Hierholzer: one route through every piece exactly once
                                                  │
                     cut into tubes ≤ max length, inside black glass where possible
                                                  │
                                  render(): bender's plan      svg(): drawing
```

## 2. File tour

- **`Font.pm`:** each glyph is a few polylines on a 4 × 6 grid, written as strings like `'0,0 2,6 4,0'`. `layout` scales them to the letter height and places each letter 5.5 units after the last.
- **`Graph.pm`:**
  - `_meet` finds where two segments meet (crossing, touching, or overlapping along a line) as a parameter along each;
  - `build` collects every such point, cuts the segments there, and merges coincident points into nodes, keyed by coordinates rounded to a thousandth of a millimetre;
  - `segments_cross` is the test for jumpers.
- **`Route.pm`:** the algorithm (section 3). `_match` is the matching and `_cut` cuts the route into tubes.
- **`Report.pm`:** groups the route into readable steps, and draws the SVG. Lit glass is drawn three times with widening translucent strokes for the glow, and doubled-back glass is offset beside its stroke.
- **`App.pm`:** option parsing, `check_text`, `parse_design` and bounded reading. Errors are thrown as hash references, so only known messages reach the user.
- **`t/tubewise.t`:** `check_plan` re-checks any plan without trusting the planner.

## 3. Key ideas

**Euler's rule.** A route that uses every edge of a connected graph exactly once exists only if 0 or 2 nodes have an odd number of edges. With 0 the route is a loop, like the O. With 2 those nodes are its ends, like the L. An H has six odd nodes: four tips, and the two middle joints, where three strokes meet. So the H can't be traced in one go without retracing something.

**Black glass fixes parity.** Adding a black connection between two odd nodes makes both even. So the cheapest fix is to pair up the odd nodes as cheaply as possible, leaving two unpaired to be the tube's electrodes. That's a **minimum-weight perfect matching**:
- two extra "free" points cost 0 to pair with anything, which lets the matching choose the ends;
- the cost of a pair is the shortest black connection between them, found by Dijkstra over two kinds of move: doubling back along a stroke (its length), or a straight jumper (its length plus the glass for two bends).

For the H the answer is 200 mm: double back down the top half of each leg, and the tube ends at the two feet. The tests check this by hand.

**Exact matching by subsets.** For a set of points *S*, `best[S]` is the cheapest way to pair them. Take the lowest point *i* in *S*: it has to be paired with some *j*, so `best[S] = min over j of cost(i, j) + best[S − {i, j}]`. That's 2ⁿ states with n choices each, fine up to 16 points (14 odd points plus the two free ends). Above that, Tubewise pairs greedily by cost and then swaps pairs (2-opt) until no swap helps, and says it did. The tests compare the exact version with trying every pairing on 60 random cases.

**Joining pieces first.** "OPEN" is four separate pieces of glass. They're joined into one graph with the shortest jumpers, chosen by Kruskal's algorithm over candidate jumpers between neighbouring letters. Candidate pairs are tried shortest first, keeping the first that doesn't cross lit glass. Then the parity step treats those jumpers like any other glass.

**Hierholzer's algorithm.** Start at an end and keep walking along unused pieces. When stuck, back up and splice in a loop from an earlier node. Each piece is pushed and popped once, so it takes linear time. The route is checked to contain every piece.

**Cutting tubes where it doesn't show.** A tube can only be so long. Walking the route, when the next piece won't fit, Tubewise cuts inside black glass, so the electrodes and joint hide behind paint:
- inside the next piece, if it is black;
- otherwise in the middle of the latest black piece already in the tube, provided what follows then fits;
- if neither is possible, the joint falls on lit glass and is counted as visible.

**Perl features used:**
- **Taint mode** (`-T`) and `use warnings FATAL => 'all'`.
- **Closures:** for the matching cost and for the coordinate transforms in the SVG.
- **Exceptions as hash references,** so internal errors can't leak as messages.
- **Text handling:** `Encode::decode` with `FB_CROAK` for strict UTF-8, and non-destructive substitution (`s///r`).
- **Testing:** `Test::More` subtests, with in-memory filehandles (`open my $fh, '<', \$string`) to drive the command line without a subprocess.

## 4. Interview questions you might get

**Q: Why is this the Chinese postman problem rather than the travelling salesman problem?**
A: The salesman must visit every *node*; the postman must traverse every *edge*. A neon tube must light every stroke (edge), and passing through a junction (node) is free. The postman problem is solvable in polynomial time: shortest paths, then a minimum-weight perfect matching on the odd nodes. The salesman problem is NP-hard. Tubewise uses the exact subset DP only because it's short to write. Edmonds' blossom algorithm would make the matching polynomial for any size.

**Q: How do you know the plan is valid without trusting the code that made it?**
A: `check_plan` rebuilds the facts from the output alone:
- every lit stroke of the graph appears exactly once as lit glass;
- each step starts where the last ended;
- no jumper crosses any stroke;
- every tube is continuous and within the length limit.

It runs on every glyph and several signs, at two tube lengths. Separately, the H and T minimums are worked by hand, and the matching is compared with brute force.

**Q: What did taint mode buy you here?**
A: Anything from outside (arguments, file contents, environment) is marked as tainted, and Perl refuses to use it in anything that touches the system (running commands, writing files) until it has been checked with a regular expression. Tubewise only reads, but taint mode guarantees a later change can't quietly pass a file name or text into a shell. The library path is also untainted with a strict pattern.

## 5. Ideas to extend it

- **Exact matching at any size:** replace the subset DP with Edmonds' blossom algorithm, so long signs get a proven minimum too.
- **Bends and the pattern:** turn the route into a full-size bending pattern, with bend radii checked for the glass diameter, and electrode positions where they can pass through the backing.
- **Fonts from a file:** read single-line SVG fonts (Hershey-style) so any script works, including joined-up handwriting, where Euler routes shine.
