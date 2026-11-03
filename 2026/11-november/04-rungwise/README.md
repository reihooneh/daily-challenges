# Rungwise

**After an at-fault accident, should you claim, or pay the repair yourself to keep your no-claim bonus? Rungwise works out the exact repair cost above which claiming is cheaper, for every rung of your insurer's bonus ladder and every year you plan to keep the policy. It also says whether bonus protection is worth its price.**

Language: Ruby (standard library only) · Field: insurance / Markov decision processes · Day: 4 November 2026

A claim drops you down the ladder: next year's discount shrinks, and it takes years to climb back. So a small claim can cost more in lost discount than it pays out. "Should I claim?" calculators compare one bill with one year's premium rise. The real answer depends on where you are on the ladder, how far a claim drops you, how many years you'll keep the car, and the chance of another accident on the way back up. Rungwise solves the whole thing:

- **A threshold table:** for every level and every number of years left, the repair bill above which claiming is cheaper.
- **The exact best rule:** a Markov decision process solved backwards by dynamic programming. Repair bills follow a log-normal distribution, with closed-form expectations, so no sampling noise.
- **Rules compared:** the expected cost of the best rule against "claim every bill over the excess" and "never claim".
- **Bonus protection, priced:** is paying extra each year so a claim doesn't move you down worth it for you?
- **Your own ladder:** any number of rungs, any discount, and any claim rule (one rung down, back to the bottom, two rungs).

## Quick start

```bash
bin/rungwise examples/car.txt
ruby -w test/test_rungwise.rb      # 12 tests, 592 assertions
```

```
RUNGWISE  Family hatchback
Base premium $1,450 a year, excess $700, at-fault accident chance 9% a year.
Repair bills: typically $2,800; half fall between $1,526 and $5,138.
Planning 5 years ahead from Rating 4, with money later discounted at 4% a year.

Claim an accident only if the repair bill is more than:
  Level (discount)   5 yrs left 4 yrs left 3 yrs left 2 yrs left  1 yr left
  Rating 1 (65%)         $1,190     $1,167     $1,133       $979       $700
  Rating 2 (55%)         $1,705     $1,651     $1,481     $1,188       $700
  Rating 3 (45%)         $2,180     $2,010     $1,722     $1,258       $700
> Rating 4 (30%)         $2,540     $2,268     $1,838     $1,327       $700
  Rating 5 (15%)         $2,025     $1,784     $1,490     $1,118       $700
  Rating 6 (0%)          $1,377     $1,262     $1,094       $909       $700
  ('>' is where you start. A smaller bill is cheaper to pay yourself than the lost discount.)

Expected cost of the next 5 years (premiums, excesses and bills you pay yourself):
  Claim only above the thresholds        $3,843
  Claim every bill over the excess       $3,900  ($56 more)
  Never claim                            $5,019  ($1,176 more)

This year: if you have an at-fault accident, claim only if the repair costs more than $2,540.
Bonus protection at $95 a year (claims don't move you down): not worth it: it costs about $228 more than it saves.
```

The thresholds peak in the middle of the ladder, where a claim costs the most climbing. They shrink as the years left run out, because there's less future discount to lose. In the last year they fall to the excess: claim anything over it.

## The policy file

```
policy Family hatchback
premium 1450            # base premium, $ a year, before discount
excess 700
accident-chance 9%      # your estimate of an at-fault accident in a year
repair-median 2800      # a typical repair bill
repair-spread 0.9       # how much bills vary (log-normal; 0.5 narrow, 1.2 very wide)
years 5                 # how long you'll keep the policy
interest 4%             # optional: money later is worth less
protection 95           # optional: price of bonus protection per year
start Rating 4
level Rating 6 discount 0% claim-to Rating 6     # worst first, best last
level Rating 5 discount 15% claim-to Rating 6
...
```

A year without a claim moves you one rung up. Exit codes: `0` advice printed, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 32 KB, read with a hard limit, 200 characters a line and 30 levels. Only regular files are opened, without following symbolic links, and the path is never printed.
- **Strict parsing:** every line has a fixed shape and every number a range (premiums, percentages, years). Errors give the line number and what was expected, never the input.
- **Safe text:** the file must be valid UTF-8, and control characters and invisible formatting characters (such as direction overrides) are refused.
- **No dynamic code:** no `eval`, no `send` built from input, no shell calls. The code and tests run warning-free under `ruby -w`.

**Known limits:**
- Rungwise is a decision aid, not financial advice, and the advice is only as good as your guesses for the accident chance and repair bills.
- It models one at-fault accident a year at most, and premiums that change only with your level. Real insurers also reprice each year.
- Some policies don't let you choose whether to claim once an incident has been reported. Check yours.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
