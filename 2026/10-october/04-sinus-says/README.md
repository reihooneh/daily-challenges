# Sinus Says 🫀

**An ECG rhythm trainer that marks your method, not just your guess.**

Reading a heart rhythm strip is a skill every medical, nursing and paramedic student has to learn. The safe way to do it is a routine: *rate, regularity, P waves, QRS width*, and only then a name. Most quiz tools skip all of that and ask "which rhythm is this?", so you can get the right answer by pattern-matching and never notice your method is broken.

Sinus Says draws a fresh 6-second strip, walks you through the routine one step at a time, and marks **every step** against measurements taken from that exact tracing.

*(The name: "Simon Says", but the one giving the orders is your sinus node, the heart's natural pacemaker.)*

## What makes it different

ECG simulators and rhythm quizzes already exist. Three things are new here:

- **It grades the method.** Five marks per strip: rate, regularity, P waves, QRS width, name. The result tells you when you named the rhythm correctly but made a wrong observation on the way ("a lucky guess will not hold up on a harder strip").
- **Answers come from measuring the drawing.** A beat detector finds the R peaks in the generated signal, the way you would with calipers. The feedback quotes the numbers: "9 complexes in 6 seconds, about 88 beats per minute".
- **Every strip has a code.** Strips are generated from a seed, never from stored images, so there are about 4 billion of them. A code like `K7Q2M` (or a link ending `#K7Q2M`) gives a friend, a tutor or a whole class the identical tracing.

It also refuses to ask unfair questions: a strip that lands on a borderline (a rate of 59 or 61, a rhythm that is only *slightly* irregular) is redrawn before you ever see it.

## Features

- Eight rhythms: normal sinus rhythm, sinus bradycardia, sinus tachycardia, atrial fibrillation, atrial flutter, sinus rhythm with PVCs, first-degree AV block, ventricular tachycardia
- Real ECG paper scale: 25 mm/s and 10 mm/mV, with small (40 ms) and large (200 ms) boxes, so counting boxes works
- Caliper marks appear over each R peak once you have answered the rate question
- Works on a phone, with a keyboard alone, with a screen reader, and in dark mode
- No dependencies, no build step, no accounts, no tracking

## Example

A strip, and the result after answering:

```text
Strip K7Q2M

  2 of 5 steps correct

  1. ✗ Rate: 15 complexes in 6 seconds, about 150 beats per minute.
  2. ✓ Regularity: The gaps between R peaks are almost identical.
  3. ✗ P waves: The baseline is a sawtooth of flutter waves.
  4. ✓ QRS width: Every QRS is narrow.
  5. ✗ Rhythm: Atrial flutter. Sawtooth flutter waves between regular, narrow QRS complexes.
```

## Tech

Plain JavaScript (ES modules), SVG, HTML and CSS. No frameworks and no packages. Tests use Node's built-in test runner.

## Run it

Browsers only load JavaScript modules from a web server, so start a tiny local one:

```bash
cd 2026/10-october/04-sinus-says
python3 -m http.server 8080
# then open http://localhost:8080
```

Any static host (GitHub Pages, Netlify) also works as-is: there is nothing to build.

## Tests

```bash
node --test tests/*.test.js
```

28 tests:

- **The physiology is right:** across hundreds of seeds, every rhythm has the features its definition requires (atrial fibrillation is always irregular with no P waves, first-degree block always has a PR interval over 200 ms, and so on).
- **The detector is right:** it finds every generated beat, within 30 ms, and nothing extra.
- **The quiz is fair:** exactly one correct option per step, and counting complexes × 10 always agrees with the measured rate.
- **Reproducible:** the same code gives the same question, sample for sample.
- **Hostile input:** script tags, path traversal, SQL fragments, Unicode look-alikes, 100,000-character strings and out-of-range numbers are all rejected.

Also checked in a real browser (desktop and phone sizes, keyboard only) with zero console errors.

## Security

This page takes two pieces of untrusted input: the code box, and the part of the link after `#`.

- **Input can only ever be a number.** A code must match 1-7 letters or digits exactly, is converted to an integer, and is range-checked. Anything else is ignored. The code shown on screen is re-created from that number, never echoed from what was typed.
- **No way to inject markup.** The page never uses `innerHTML`, `eval` or anything similar. Text is written with `textContent`, and the drawing is built from numbers only (a test checks the path contains nothing but digits and drawing commands).
- **Strict Content-Security-Policy.** Only this site's own scripts and styles can run: no inline scripts, no third-party code, and `connect-src 'none'` so the page cannot send data anywhere.
- **Nothing is collected or stored.** No cookies, no local storage, no analytics, no network requests. Your score lives in memory and disappears when you close the tab.
- **Private sharing.** The strip code sits after `#` in the link, which browsers do not send to servers.
- **Bounded work.** A strip is always 1,500 samples and generation has a fixed retry limit, so no input can make the page hang.
- **No dependencies,** so there is no supply chain to attack.

**Known limits, stated honestly:**

- **This is a learning tool, not a medical device.** The tracings are simplified mathematical shapes (one lead, eight rhythms, no artefact). Never use it to interpret a real ECG.
- Marks are for learning, not assessment: everything runs in your browser, so anyone can read the answers in the code.
- The security policy is set in the page itself; a host should also send it as an HTTP header, along with HTTPS.
- No software can promise it is 100% secure; these are the protections in place.
