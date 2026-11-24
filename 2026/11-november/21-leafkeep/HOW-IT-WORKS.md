# How Leafkeep works

## Architecture

```
src/lib.rs     the model: teas, pots, one infusion, the steep-time search, sessions, calibration
src/main.rs    the command line: options, reading the CSV, printing tables
tests/         equal strength, mass balance, the exact solution, calibration, hostile input
examples/      refractometer readings from an oolong session
```

## The model

**Two pools.** A gram of leaf holds `soluble` grams that can dissolve. A share sits on the surface
(fast pool); the rest is inside the rolled leaf (slow pool). Each pool empties at a first-order rate:
in a short step `h`, the pool loses `S (1 − e^{−k h})`.

**Temperature.** Rates are quoted at 95 °C and scaled by the Arrhenius factor
`exp(−Eₐ/R (1/T − 1/T₉₅))`. The water poured in cools towards room temperature with the pot's time
constant (a glass pot fastest, clay slowest), so a long steep runs cooler than a short one.

**Unfurling.** The slow pool's rate is multiplied by `0.15 + 0.85 (1 − e^{−contact/unfurl})`, where
`contact` is the total time the leaves have steeped so far. Tightly rolled oolong and compressed
pu-erh take minutes to open; green tea opens almost at once. This is why rolled oolongs get *better*
in the second and third cups.

**Held liquor.** Wet leaves hold about 2.5 ml per gram. The first pour soaks into them; after that,
each cup gets the water poured in plus the liquor held from the last one, and leaves the same amount
behind.

**Equal strength.** A cup's strength rises with steep time, so for each infusion Leafkeep bisects
for the time that matches the first cup (40 halvings of 0.5–900 s). If even 900 s can't reach it, the
leaves are spent.

**Calibration.** Given measured TDS for a session, Leafkeep scales the tea's soluble content and
both rates. It searches a 7×7×7 grid over the logarithms of the three multipliers, then shrinks the
grid three times around the best point: a derivative-free search that can't run away, with the
soluble fraction capped at a physical 60 %.

## Language features worth noticing

- Plain `Copy` structs (`Tea`, `Brew`, `Leaves`) make "what if I steeped for t seconds?" a pure
  function: `infuse` takes the leaves by reference and returns new ones, so the search can try many
  times without undoing anything.
- `let … else` keeps the CSV parser flat: a line that isn't exactly two fields returns early.
- Struct update syntax (`Tea { soluble: …, ..b.tea }`) builds the fitted tea from the preset.
- Output is built into a `String` and written once, so `leafkeep plan | head` can't panic on a closed pipe.

## Interview questions

**Why bisection rather than solving for the time directly?** The water cools and the slow pool
opens during the steep, so strength has no closed form in time. It is monotonic, though, and
bisection on a monotonic function always converges: 40 halvings give a time far finer than anyone
can pour.

**How do you know the integration is right?** A test switches off cooling and unfurling, where the
answer has a closed form, `M (1 − e^{−kt}) / V`, and matches it to 1e-9. Another checks mass
balance across a session: what left the leaves is in the cups or in the liquor they still hold.

**Why a grid search for calibration instead of gradient descent?** Three parameters, a cheap model
and a bumpy error surface (the session is a chain of infusions). A shrinking grid is predictable,
bounded in time and needs no derivatives; the test shows it recovers a known tea from its readings.

## Extensions

1. Read a smart scale and timer over Bluetooth and log sessions automatically.
2. Add a third, very slow pool for aged pu-erh, which gives up colour long after flavour.
3. Learn the unfurling time from the shape of the strength curve across a calibration session.
