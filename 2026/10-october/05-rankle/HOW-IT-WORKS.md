# How Rankle works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 ballots.txt ──▶ Ballots.parse ──▶ candidates + ballots (validated)
                                          │
                 ┌────────────────────────┼─────────────────────────┐
                 ▼                        ▼                         ▼
          Methods (5 rules)      Analysis.spoilers           Analysis.cycle
          who wins under each    remove a loser, re-run,     A beats B beats C
                 │               did the winner change?      beats A?
                 └────────────────────────┼─────────────────────────┘
                                          ▼
                                   Report.render ──▶ text + exit code
```

## 2. File tour

| File | Job |
|---|---|
| `lib/rankle/ballots.rb` | Reads and validates the ballot file. The only code that touches raw input. |
| `lib/rankle/methods.rb` | The five counting rules. Pure functions. |
| `lib/rankle/analysis.rb` | Spoilers, cycles and the "loses to everyone" check. |
| `lib/rankle/report.rb` | Turns results into sentences. |
| `lib/rankle.rb` | The command line: arguments, reading the file, exit codes. |
| `bin/rankle` | Three lines that start the program. |
| `test/test_rankle.rb` | 28 tests. |

### `ballots.rb`: never trust the file
Each line becomes a `Ballot` with a `count` and a `ranking` (an array of names, best first). A line with a count stands for that many identical ballots, so "18 voters" is one object, not eighteen. Validation happens here and nowhere else: once data leaves `parse`, the rest of the program can assume it is clean. That idea is called a **trust boundary**.

### `methods.rb`: five rules, one building block
Most rules are built from one helper, `first_choices(standing, ballots)`: "among the candidates still standing, who does each ballot rank highest?"

- **Plurality** is `first_choices` once.
- **Two-round runoff** is `first_choices` for everyone, then again for just the top two.
- **Instant runoff** is `first_choices` in a loop, removing the weakest candidate each time. A ballot whose choices have all been eliminated is *exhausted* and stops counting.
- **Borda** gives points by position instead.
- **Condorcet** builds a **pairwise matrix**: `matrix[a][b]` is how many voters prefer `a` to `b`. The Condorcet winner is whoever wins every one of their rows.

Every rule returns an *array* of winners: one name normally, several for an exact tie, empty when Condorcet has no answer. Returning the same shape from every rule is what lets the rest of the code treat them identically.

### `analysis.rb`: the spoiler hunt
A **spoiler** is a candidate who doesn't win but changes who does. The test is simple and brute-force: for each rule, for each loser, delete that candidate and count again. If the winner is different, report it. Because the counting rules already accept "the candidates still standing", removing someone is just passing a shorter list.

A fair rule shouldn't care whether an irrelevant loser is on the ballot. This property is called **independence of irrelevant alternatives**, and **Arrow's impossibility theorem** proves that no ranked voting rule can satisfy it together with a few other reasonable-sounding conditions. Rankle lets you watch that theorem happen.

### `report.rb` and `rankle.rb`
`Report.render` returns a string and prints nothing, so tests can check the wording. `Rankle.run` takes its input and output streams as arguments, which lets tests run the whole command line in memory.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Ranked ballot | A voter lists candidates in order of preference |
| Condorcet winner | Someone who would beat every rival in a one-on-one contest |
| Condorcet paradox | A beats B, B beats C, C beats A: majorities can go in a circle |
| Spoiler effect | A losing candidate changes the winner by splitting votes |
| Exhausted ballot | In instant runoff, a ballot with no remaining choices |
| Trust boundary | The one place where outside data is checked before the program relies on it |
| Terminal escape injection | Hidden codes in text that make a terminal do things when printed |
| ReDoS | A regular expression that takes far too long on a crafted input |

### Ruby features you met here
- **Modules with `module_function`**: a namespace of plain functions, called as `Methods.borda(...)`, with no objects to create.
- **`Struct`**: a tiny class with named fields in one line (`Ballot = Struct.new(:count, :ranking)`).
- **Blocks and enumerables**: `select`, `reject`, `find`, `all?`, `sum`, `to_h`, `each_with_index`. Most loops in Ruby are written this way.
- **`permutation(3)` and `combination(2)`**: every ordered triple or unordered pair, built into arrays.
- **Lambdas**: `beats = ->(a, b) { ... }` stores a small function in a variable.
- **Unicode-aware regex**: `\p{L}` means "any letter in any language", so `Zoë` and `李雷` are valid names.
- **`# frozen_string_literal: true`**: string literals can't be modified by accident.
- **Custom exception** (`InputError`): expected problems become one clean line, not a stack trace.
- **Minitest**: Ruby's built-in test library.

## 4. Interview questions you might get

**Q: How do you detect a spoiler?**
A: By definition. For each voting rule I remove one losing candidate, re-run the count, and compare the winner. If it changed, that candidate is a spoiler under that rule. It's brute force, but with at most 20 candidates and 5 rules that is at most about 100 recounts, so it's instant, and it's obviously correct, which matters more here than cleverness.

**Q: Your tool prints text from a file to the terminal. What could go wrong?**
A: Terminals obey escape sequences, so a file could contain codes that clear the screen, fake output or change the window title. I reject any line containing control or invisible formatting characters before parsing, restrict names to a small set of safe characters, and never copy input into error messages. There's a test for each.

**Q: Why does every method return an array instead of a single winner?**
A: Elections can tie, and Condorcet can have no winner at all. If I returned a single name I'd have to invent a tie-break and hide it. Returning a list makes ties and "no winner" ordinary values that the report and the spoiler check handle without special cases.

## 5. Ideas to extend it yourself

1. **More rules:** approval voting, Coombs' method, or ranked pairs (which always produces a winner even when there's a cycle).
2. **Monotonicity check:** find a case where ranking a candidate *higher* makes them lose under instant runoff. It can really happen.
3. **Round-by-round output** for instant runoff, showing which ballots moved where.
