# How Catchbreath works

## 1. Architecture

```
song.txt ─(Cli: plain file, 64 KB)─▶ Song::parse
   settings (title, tempo, breath, catch) + notes [{text, beats, rest, joins, lineEnd}]
        │
        ▼
Planner::plan ── dynamic programming over the gaps between notes
   gapCost(i)      where a breath may go and what it costs (null inside a word)
   phraseCost(s)   comfort near the limit, a heavy penalty over it
        │  best[e] = min over p of best[p] + phraseCost(sung time p+1..e) + gapCost(e)
        ▼
Report::render ── lyrics with ’ marks, a phrase table with bars, and flagged stretches
```

## 2. File tour

| File | What's in it |
|---|---|
| `src/Song.php` | The file format: settings, `syllable:beats` tokens, words joined with `-`, rests `_`, all the checks, and `Text::clean` for safe quoting. |
| `src/Planner.php` | The cost of each place to breathe, the cost of a phrase, and the dynamic program with read-back. |
| `src/Report.php` | The marked lyrics and phrase table. |
| `src/Cli.php` | Arguments, safe file reading, `--breath` and `--tempo` overrides, exit codes. |
| `bin/catchbreath` | Loads the classes and runs. |
| `tests/run.php` | 1,091 checks, including the brute-force comparison. |

## 3. Key concepts and language features

**Breathing as a shortest path.** Number the gaps after each note. A plan is a choice of gaps, and between two consecutive breaths lies a phrase. The total cost is the sum of each breath's cost plus each phrase's cost, and each phrase's cost depends only on its two ends. That's a shortest path through the gaps, so `best[e]`, the cheapest way to sing up to note `e` and breathe there, is the cheapest `best[p]` plus the phrase from `p + 1` to `e` plus the breath at `e`. It's O(n²) with n notes, and in practice far less.

**The phrase length in O(1).** Prefix sums of beats give any stretch's length by subtracting two numbers. Rests at either end of a phrase don't count (you're breathing in them), so two more arrays record the nearest sung note on each side of every position.

**Soft limits instead of failure.** A phrase over the singer's limit isn't forbidden. It costs 100 plus 200 per second over, far more than any choice of breath place (at most 21). So if a plan within the limit exists, the planner finds it. If one can't exist (a note held longer than a breath), it still returns the best plan and flags the stretch, instead of giving up.

**Early stopping.** Looking back from note `e`, phrases only get longer. Once one fitting phrase has been found and the current one is more than a second over the limit, every longer one costs more than that fit, so the loop stops. That keeps the largest songs fast.

**PHP features:**
- `declare(strict_types=1)` throughout, so a string can never quietly pass for a number;
- readonly promoted constructor properties (`private readonly Song $song`);
- `str_ends_with` and `str_starts_with`;
- `mb_*` functions and Unicode regular expressions (`\p{L}`, `/u`), so syllables like "o'" and curly quotes work;
- `INF` and `is_finite` for unreachable states;
- `Cli::run` takes its streams as parameters, so the tests run it in memory with `php://memory`.

## 4. Interview questions

**Q: How do you know the dynamic program finds the best plan?**
A: The cost splits into independent pieces per breath and per phrase, so it has optimal substructure: the best plan ending in a breath at `e` contains the best plan up to its previous breath. The tests also check it directly against brute force. On 300 random songs of up to 11 notes, it tries every subset of allowed breath places and compares the best cost with the planner's.

**Q: Why make over-long phrases a cost rather than a rule?**
A: Real songs have notes longer than a singer's breath. With a hard rule, there'd be no plan at all and nothing useful to say. A big penalty keeps the planner honest: it never goes over when it doesn't have to, because the penalty outweighs any breath cost. When it has to, it still produces the best plan and says exactly which stretch is the problem.

**Q: What would a hostile song file try, and what stops it?**
A: There are several angles:
- **Size:** a huge file or millions of notes. The file is capped at 64 KB and the notes at 5,000.
- **Strange numbers:** values like `1e5`, `NaN` or negatives. The regex only accepts plain decimals, and the ranges are checked.
- **Encoding:** invalid UTF-8 or NUL bytes, which are refused.
- **Terminal escape codes**, which are cleaned before being echoed back.
- **Symlinks** to files the user didn't mean to share, which are refused.

There's no `eval` and no shell, so the file is only ever data.

## 5. Extension ideas

- **Choir staggered breathing:** for a section of k singers, choose k plans so that at every gap at most a set number breathe at once. The long notes are then covered by the section as a whole.
- **Read MusicXML:** take the syllables and durations straight from a score, and write the breath marks back into it.
- **Learn the costs:** let a teacher mark a few songs by hand, then fit the costs to match.
