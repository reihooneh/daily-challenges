# How Sinus Says works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 code "K7Q2M" ──▶ seed (a number) ──▶ seeded random generator
                                             │
                        pick a rhythm, schedule the beats
                                             ▼
                each beat = P + QRS + T bumps added together
                                             ▼
                    1,500 voltage samples (6 s at 250 per second)
                         │                         │
                  draw as an SVG path       detect R peaks, measure
                         │                  rate and regularity
                         ▼                         ▼
                    the strip               the answer key ──▶ 5 questions
```

The key idea: **the answers are measured from the same signal that gets drawn**, so the quiz can never disagree with the picture.

## 2. File tour

| File | Job |
|---|---|
| `src/rng.js` | Seeded random numbers; turning codes into seeds and back |
| `src/rhythms.js` | Builds the heartbeat signal for each of the eight rhythms |
| `src/measure.js` | Finds R peaks and works out rate, regularity, P waves, QRS width |
| `src/quiz.js` | Builds the five questions and marks answers |
| `src/render.js` | Turns samples into an SVG path at real ECG paper scale |
| `src/app.js` | The only file that touches the page: buttons, drawing, score |
| `index.html`, `styles.css` | Structure and looks |
| `tests/` | 28 tests for everything except `app.js` (which is checked in a real browser) |

### `rng.js`: why not `Math.random()`?
`Math.random()` gives different numbers every time and can't be told where to start. A **seeded** generator (here `mulberry32`, about six lines of bit-mixing) produces the same sequence whenever it starts from the same seed. That is what lets a code recreate a strip. The code itself is just the seed written in **base 36** (digits 0-9 then letters A-Z), which is shorter than writing it in decimal.

### `rhythms.js`: drawing a heartbeat with maths
A **Gaussian** is the bell-curve shape `exp(-(t - centre)² / (2 × width²))`. Change the width and height and it becomes any smooth bump:

- **P wave** (atria contracting): small, wide, before the spike
- **QRS** (ventricles contracting): a tiny dip (Q), a tall thin spike (R), a small dip (S)
- **T wave** (ventricles resetting): medium, rounded, after the spike

One beat is those bumps added together. A *rhythm* is then a **schedule**: a list of beat times, and for each beat whether it has a P wave, how long its PR interval is, and whether it is wide.

| Rhythm | How the schedule makes it |
|---|---|
| Normal sinus / brady / tachy | Evenly spaced beats; only the rate differs |
| First-degree AV block | Same, but the P wave is moved further from the QRS (PR over 200 ms) |
| Atrial fibrillation | Every gap is a different random length, no P waves, wobbly baseline |
| Atrial flutter | Sawtooth baseline at 300 per minute; a QRS every 4th (or 2nd) tooth |
| PVCs | A wide beat with no P wave arrives early, and the next normal beat is skipped (the pause) |
| Ventricular tachycardia | Fast, evenly spaced wide beats with no P waves |

**The fairness check (`isClearCut`):** random timing sometimes produces a strip that is honestly ambiguous, like a rate of 59. Asking "slow or normal?" there would be unfair, so the generator redraws until both ways of reading the rate agree and the rhythm is clearly regular or clearly not. The redraws use the same seeded generator, so the result is still reproducible.

### `measure.js`: electronic calipers
`detectBeats` walks through the samples looking for a point that is above 0.5 mV, is the highest in its neighbourhood, and is at least 200 ms after the previous peak. That last rule is the **refractory period**: heart muscle physically cannot fire again that quickly, so anything inside it is the same beat. Real heart monitors use the same idea.

From the peaks:
- **Rate** = 60 ÷ average gap between peaks
- **Regularity** uses the **coefficient of variation**: the spread of the gaps divided by their average. Under 8% counts as regular.

### `quiz.js`: questions as data
Each step is a plain object: a prompt, the options, the right answer and an explanation. `grade` just compares. Keeping this free of any page code is what makes it testable from the command line.

### `render.js`: real paper scale
ECG paper moves at 25 mm per second, and 10 mm of height is 1 millivolt. At 10 pixels per mm, a small box is 10 px (40 ms) and a large box is 50 px (200 ms). Because the scale is real, the clinical rules of thumb work on screen.

### `app.js`: the page
Holds the current question and score in one `state` object, redraws when it changes, and listens for clicks. It builds every element with `createElement` and `textContent`.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Seeded PRNG | A "random" sequence you can replay by starting from the same number |
| Gaussian | A bell-shaped bump; add several to build a waveform |
| Sample rate | How many measurements per second (250 here) |
| Peak detection | Finding the tall spikes in a signal while ignoring small bumps |
| Refractory period | A cool-down after each beat; used to avoid counting one beat twice |
| XSS (cross-site scripting) | Tricking a page into running an attacker's script, usually via text that gets treated as HTML |
| Content-Security-Policy | A rule list telling the browser which scripts and connections are allowed |
| Pure function | Same input, same output, touches nothing else; easy to test |

### JavaScript features you met here
- **ES modules** (`import` / `export`): each file declares what it shares. No bundler needed.
- **`Float64Array`**: a fixed-size array of numbers, faster and leaner than a normal array for signals.
- **Bit operators** (`>>>`, `^`, `Math.imul`): 32-bit integer maths, used by the random generator. `>>> 0` forces a number to be an unsigned 32-bit integer.
- **Closures**: `mulberry32(seed)` returns a function that remembers its own private state.
- **Destructuring and spread** (`const [value, label] = option`, `[...items]`).
- **Optional chaining and `??`**: `a?.b` doesn't crash if `a` is missing; `x ?? y` uses `y` only when `x` is null or undefined.
- **`createElementNS`**: SVG elements live in their own namespace, so `createElement` won't work for them.
- **`node --test`**: Node's built-in test runner, with `node:assert/strict`.

## 4. Interview questions you might get

**Q: How does a five-character code recreate a whole ECG?**
A: The code is a 32-bit seed in base 36. Everything random in the strip (which rhythm, the rate, the beat timing, the noise) is drawn from a seeded generator, so the same seed replays the same sequence and produces the identical signal. Nothing is stored or sent anywhere.

**Q: How do you know the quiz's answers are right?**
A: Two ways. The answer key is measured from the generated signal by a peak detector, not written by hand, so it can't disagree with the drawing. And the tests check hundreds of seeds per rhythm against the clinical definition, plus that the detector finds exactly the beats that were generated.

**Q: A link can carry a strip code. Couldn't someone craft a malicious link?**
A: The value after `#` is treated as untrusted. It must match 1-7 letters or digits, is parsed to an integer and range-checked; otherwise it's ignored. Even the code displayed is regenerated from that integer. The page never uses `innerHTML`, and a Content-Security-Policy blocks inline and third-party scripts as a second layer, so there's no path from a link to running code.

## 5. Ideas to extend it yourself

1. **More rhythms:** second-degree block (some P waves with no QRS after them) or a paced rhythm with pacing spikes.
2. **Measure the PR interval yourself:** let the user drag two caliper lines on the strip and mark the distance.
3. **Spaced repetition:** track which rhythms you miss most and show those more often.
