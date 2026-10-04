# Rankle 🗳️

**One set of ballots, five voting rules, and the spoilers hiding in the result.**

"Who won?" sounds like a question with one answer. It isn't. The same ballots can elect different people depending on the counting rule, and a candidate who loses can still decide who wins just by being on the ballot. Rankle takes a file of ranked ballots, counts it five ways, and tells you plainly where the rules disagree and who the spoilers are.

*(To "rankle" is to cause lasting irritation, which is what election results do when the rule picks the winner. Also: rank + ballot.)*

## What makes it different

Ranked-ballot calculators exist, and they print tables of numbers. Rankle is built around the *argument* instead:

- **A spoiler hunt.** For every rule, it removes each losing candidate in turn and re-runs the election. If the winner changes, that candidate is a spoiler, and Rankle says exactly what would have happened without them.
- **A verdict in words.** "The same ballots produce 5 different outcomes. The rule decides the election."
- **Paradox warnings.** It reports a rock-paper-scissors cycle (the Condorcet paradox), and warns when a rule elects the candidate who would lose one-on-one against *every* opponent.
- **Scriptable.** Exit code `0` means every rule agrees, `1` means they don't, so a club or class can check a result automatically.

## The five rules

| Rule | How the winner is chosen |
|---|---|
| Plurality | Most first choices. Everything else on the ballot is ignored. |
| Two-round runoff | The top two go head to head. |
| Instant runoff | Eliminate the last-placed candidate and move those ballots to their next choice; repeat until someone has a majority. |
| Borda count | Points for position: first of five earns 4, second 3, and so on. |
| Condorcet | The candidate who beats every other candidate one-on-one, if there is one. |

## Example

A classic from voting theory, 55 voters and five candidates (`examples/five-winners.txt`):

```text
$ rankle examples/five-winners.txt
55 voters, 5 candidates: Ana, Dev, Eli, Cai, Bo

  Plurality         Ana
  Two-round runoff  Bo
  Instant runoff    Cai
  Borda count       Dev
  Condorcet         Eli

The same ballots produce 5 different outcomes. The rule decides the election.
Warning: Ana loses one-on-one to every other candidate, yet wins under Plurality.

Spoilers (a loser whose presence changes the winner):
  Plurality: without Dev, the result changes from Ana to Cai.
  Plurality: without Cai, the result changes from Ana to Bo.
  Plurality: without Bo, the result changes from Ana to tie: Ana, Eli.
  Two-round runoff: without Ana, the result changes from Bo to Dev.
  Two-round runoff: without Dev, the result changes from Bo to Cai.
  Instant runoff: without Ana, the result changes from Cai to Dev.
  Borda count: without Cai, the result changes from Dev to Eli.
```

Nine friends choosing lunch (`examples/lunch.txt`):

```text
Cycle: Pizza beats Sushi, Sushi beats Tacos, and Tacos beats Pizza. The group has no consistent preference (the Condorcet paradox).
```

## Ballot file format

```text
# comments and blank lines are ignored
18: Ana > Dev > Eli > Cai > Bo     # 18 voters with this ranking
Bo > Eli                           # no count means one voter
```

Best choice first. Candidates a voter leaves off are treated as ranked below everyone they listed.

## Tech

Ruby 3.1+, standard library only. No gems to install. Tests use Minitest, which ships with Ruby.

## Run it

```bash
cd 2026/10-october/05-rankle
ruby bin/rankle examples/five-winners.txt
cat my-ballots.txt | ruby bin/rankle -
```

| Exit code | Meaning |
|---|---|
| `0` | Every rule agrees on the winner |
| `1` | The rules disagree (or one has no winner) |
| `2` | Invalid input |

## Tests

```bash
ruby -w test/test_rankle.rb
```

28 tests, 190 assertions:

- **Correct counting:** the classic five-winner election, Borda totals checked against a hand calculation, pairwise counts that must add up to the number of voters, ties, truncated ballots and exhausted ballots.
- **Paradoxes and spoilers:** the Condorcet cycle, the textbook vote-splitting spoiler, and a check that results never depend on the order of the ballots.
- **Hostile input:** terminal escape codes, invisible Unicode characters, script tags, shell fragments, path traversal, invalid UTF-8, oversized files, and lines designed to slow the parser down.

## Security

Rankle reads an untrusted text file and prints candidate names to a terminal, so both directions are guarded.

- **No terminal hijacking.** A text file can contain escape codes that clear the screen, change colours or rewrite the window title when printed. Rankle rejects any line containing control or invisible formatting characters, and names may only use letters, digits, spaces and `. ' _ -`.
- **Error messages never echo the input.** They give the line number and the rule that was broken, nothing copied from the file.
- **Everything is bounded.** At most 1 MB, 10,000 lines, 20 candidates, 40 characters per name and one billion voters. Only the first 1 MB of a file is ever read, so a huge file can't exhaust memory. The largest allowed election is tested to finish in seconds.
- **No slow patterns.** The parser's regular expressions have no nested repetition, and a test times them on pathological lines.
- **Nothing dangerous in reach.** No `eval`, no shell commands, no network, no file writes, no deserialisation. It reads the one file you name and nothing else.
- **Exact arithmetic.** Counts are integers (Ruby integers never overflow), so there are no rounding errors in a close result.
- **No dependencies,** so there is no supply chain to attack.

**Known limits, stated honestly:**

- This is an analysis and teaching tool, **not certified election software**. Don't use it to run a binding vote.
- Real election laws have detailed tie-breaking rules. Rankle reports exact ties as ties, and in instant runoff it eliminates all candidates tied for last place together.
- The spoiler check removes one candidate at a time; it does not search for pairs of candidates who only change the result together.
- It cannot tell whether the ballots themselves are genuine.
- No software can promise it is 100% secure; these are the protections in place.
