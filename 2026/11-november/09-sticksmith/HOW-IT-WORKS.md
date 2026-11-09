# How Sticksmith works

## 1. Architecture

```
passage.txt ──readPassage (regular file, ≤64 KB, UTF-8)──▶ parsePiece ──▶ Piece
                                                                         │ notes: bar, slot, beat, drums for the hands
                       ┌─────────────────────────────────────────────────┤
                       ▼                                                 ▼
                solve(piece, tempo)                           alternating(piece)
        dynamic programme over the notes                  R L R L, reset by chords
                       │                                                 │
                       ▼                                                 ▼
             evaluate(sticking) ◀──────── the same cost model ───────▶ evaluate(sticking)
                       │
      fastestTempo: binary search on "is there any playable sticking?"
                       │
                       ▼
       analyse ──▶ report: chart under each bar, practice notes, summary, comparison
```

## 2. File tour

- **`src/parse.js`:** the passage format.
  - The default kit is a right-handed layout in metres, with negative values to the drummer's left.
  - It reads `drum`/`foot` lines, and `bar` lines with one token per grid slot.
  - Each slot that has something for the hands becomes a `Note` with its beat position and whether it falls on a beat.
  - Every limit lives in `LIMITS`.
- **`src/stick.js`:** the hands and the search.
  - `PLAYERS` holds three sets of hand speeds; `COSTS` holds the price of each awkward thing.
  - `stroke` decides whether one hand can play one drum at one moment, and at what cost.
  - `noteCost` adds what depends on both hands.
  - `evaluate` replays any sticking; `solve` finds the cheapest one; `fastestTempo` is the binary search.
- **`src/explain.js`:** `where` turns a note into "bar 3 · 2.1"; `chart` lines the sticking up under the tokens; `report` writes the words.
- **`bin/sticksmith.js`:** the options and the careful file read.

## 3. Key concepts

**What makes a sticking playable.** Every physical limit is a minimum time between two strokes of the same hand:
- **Single strokes:** at least `single` apart (120 ms for average hands).
- **A double:** two strokes on the same drum can be as close as `double` (65 ms), because the stick rebounds. The stroke after must wait a full `single`, so there are no triples.
- **Moving:** a hand needs `move + perMetre × distance` to reach a different drum.

Because each rule is a lower bound on a gap, slowing down can only make things easier. That makes playability monotone in tempo, and lets a binary search find the fastest tempo; a test checks this on random passages.

**What makes a sticking good.** Among playable stickings, the cost adds up:
- **Hand travel:** moving is free when a hand has plenty of time, and costs in full when it's rushed.
- **Rushing:** one hand working faster than about 55% of its top speed.
- **Doubles.**
- **Crossovers:** hands swapping sides outright, scaled by how little time there is to do it.
- **The weaker hand:** a little for each stroke it plays, more for reaching far towards the lead side, and most for taking a beat on its own.

Staying crossed costs nothing, because a right hand over the left on the hi-hat is how most people play a groove.

**The search state.** After note *i*, Sticksmith remembers:
- which hand played it, and on which drum;
- where the other hand is, and which note it last played;
- whether each hand has just played the fast second stroke of a double.

That's enough to price the next note exactly, so the dynamic programme is exact. It's a shortest path through a layered graph, one layer per note.

Two details keep it small:
- A two-drum note is stored as "the right hand played it". The left hand's last note is then the same note, so nothing is lost.
- Once a hand's last stroke is more than 1.5 s ago, that time is forgotten (the position is kept), and the hand counts as rested: its next move is free. Every speed limit is far shorter than 1.5 s, so this never changes what is playable. It's part of the cost model, and `evaluate` applies the same rule, so the search is exact for that model.

**Checking it.** `evaluate` applies the same rules to a fixed sticking. The tests enumerate every sticking of 60 random passages (up to 2¹⁰ each) at three tempos for three kinds of player. They require:
- the search's cost equals the best of all of them;
- "impossible" agrees in both directions;
- the chosen sticking replays at exactly the claimed cost.

**JavaScript features used:**
- ES modules and `node:test` with no dependencies;
- JSDoc types checked by `tsc --checkJs --strict`, so the code stays plain JavaScript but is type-checked;
- `Object.freeze` for the constants;
- `Map` keyed by a compact string for the search layers;
- a fatal `TextDecoder` to refuse invalid UTF-8;
- `Object.hasOwn` to check options without touching the prototype.

## 4. Interview questions

**Q: Why a dynamic programme rather than a greedy "nearest free hand" rule?**
A: Because a choice now constrains choices later. Taking a note with the right hand because it's closer can leave that hand too far from the crash two notes later. Greedy can't see that; the dynamic programme carries every reachable situation forward and keeps the cheapest way to each. The state is small (hand × drum × other hand's drum × its last note × two flags) and the horizon trick bounds it. So it's exact and still fast: a 64-bar passage solves in well under a second.

**Q: How do you know the binary search for the fastest tempo is valid?**
A: Binary search needs a monotone predicate. Every constraint has the form "gap between strokes ≥ some fixed time". Scaling the tempo up shrinks every gap by the same factor, so any sticking that fails at tempo T also fails at any faster tempo, and the existence of a playable sticking is monotone too. The costs change with tempo, but feasibility doesn't depend on costs. A test sweeps tempos on random passages and checks the answer flips exactly once.

**Q: The cost weights are made up. How would you make them trustworthy?**
A: I'd treat them as parameters to fit, not truths. Here's how:
- Collect stickings that teachers or published method books give for a set of fills.
- Fit the weights so the search reproduces them, for example with inverse optimisation: find weights under which the expert sticking is optimal, maximising the margin.
- Validate on fills held out from the fit.
- Separately, measure a player's real single-stroke and double-stroke speeds with a practice pad and a microphone, and set the `PLAYERS` numbers from those.

## 5. Extension ideas

- **Feet too:** treat kick and hi-hat foot as two more limbs with their own speeds, for double-pedal and left-foot clave patterns.
- **Rudiment hints:** recognise known stickings (paradiddles, six-stroke rolls) in the answer and name them, or prefer them with a small bonus.
- **Learn from you:** time a few bars of your own playing from audio or MIDI, fit your `single`, `double` and travel speeds, and re-stick for your hands.
