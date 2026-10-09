# Changeling 🪙

**Plans the cash float for a market stall: which coins and notes to bring, so you can give everyone their change.**

Anyone who has run a fete stall, a market table or a school canteen knows the moment: someone hands over a $20 for a $4 lemonade and you have no $1 coins left. Advice on how much float to bring is guesswork ("bring $100 in coins"). Changeling works it out. Describe your prices, how many customers you expect and how they usually pay, and it simulates hundreds of market days to find the mix of coins and notes, within your budget, that leaves the fewest customers stuck. It also tells you which price changes would cut the coins you need.

## What makes it different

Change calculators work out the change for *one* sale. Cash-counting apps tally a till at the end of the day. Changeling plans the float *before* the day starts:

- **Simulates real days.** Customers buy one or more items, totals are rounded to 5c like real Australian cash, and they pay with exact money, the smallest note that covers it, or a $20 fresh from the ATM. Their notes go into the drawer and become change for later customers.
- **Optimises the mix, not just the total.** A search tries adding and exchanging coins and notes, and keeps whatever leaves the fewest customers stuck.
- **Gives exact change properly.** If the obvious biggest-coin-first way fails (60c from one 50c and three 20c), it searches for any combination that works, as a good cashier would.
- **Suggests price nudges.** Moving one price to a rounder amount can cut coin demand a lot.
- **Speaks bank.** Coins are shown as bank rolls plus loose coins, ready to order.

## Example

```text
$ ./changeling examples/lemonade.stall
CHANGELING  Lemonade and cookies at the school fete
120 cash customers a day, float budget $150.00, tested on 100 simulated days

RECOMMENDED FLOAT  ($150.00)
  5c   x 60   1 roll + 20        $3.00
  10c  x 80   2 rolls            $8.00
  20c  x 40   2 rolls            $8.00
  50c  x 80   4 rolls           $40.00
  $1   x 51   2 rolls + 11      $51.00
  $2   x 20   20 loose          $40.00

RISK                                   this float     typical float*
  Customers you can't give change to   15.97 a day    41.97 a day
  Days with at least one stuck sale    76%            100%
  Sales lost for want of change        $89.77 a day   $235.57 a day
  * the same budget split evenly across 50c, $1, $2, $5 and $10
  When it does go wrong, you're short of: $1 (38%), $2 (32%), 50c (26%)

PRICE NUDGES  (fewer awkward amounts, so fewer coins needed)
  lemonade       $4.00 -> $5.00   stuck customers 15.97 -> 5.67, float needed $150.00
  cookie         $2.50 -> $3.00   stuck customers 15.97 -> 13.35, float needed $150.00
  brownie        $3.50 -> $4.00   stuck customers 15.97 -> 11.49, float needed $149.50
```

This stall is short of coins: most change involves $1, $2 and 50c coins, and only customers paying exact money bring new ones in. The best $150 float still leaves about 16 customers a day stuck, against 42 with a typical even split. Pricing lemonade at $5 instead of $4 cuts it to under 6, because a $5 note then needs no change at all.

## Describing a stall

```text
title     Lemonade and cookies at the school fete
budget    150        # dollars you can put in the float
customers 120        # cash customers in a day
basket    1-2        # items each customer buys
item lemonade 4.00 weight 5
item cookie   2.50 weight 4
pays exact    20     # per cent who pay with exact money
pays smallest 50     # ... with the smallest note that covers it
pays 20       25     # ... with a $20 note
pays 50        5
```

`weight` is how popular an item is, relative to the others. The `pays` lines must add up to 100. If you leave them out, a typical mix is used.

## Usage

```bash
make                                    # build
./changeling examples/lemonade.stall
./changeling --days 300 --seed 7 my-stall.txt
```

Exit codes: `0` the float covers the day (fewer than one stuck customer every two days), `1` customers will still be stuck, `2` the input could not be used.

## Tech

Java 17, standard library only: no build tool, no dependencies. It compiles with `-Xlint:all -Werror` and comes with a small self-contained test runner.

## Tests

```bash
make test
```

81 checks, including:

- **Change-giving against brute force:** on 3,000 random drawers, change is possible exactly when trying every combination says so. The right amount is always taken, and the exact search always uses the fewest coins.
- **Australian rounding:** every last digit from 1c to 9c.
- **The search:** the plan stays within budget, and beats the typical float, an empty float and 40 random floats that spend the same money.
- **Simulation:** a huge float never leaves anyone stuck, the same seed always gives the same days, and very busy stalls are automatically cut to a safe size.
- **Hostile input:** markup, escape codes, right-to-left override and NUL characters, non-ASCII text, `1e9`, negative and zero prices, duplicate items, percentages that don't add up, oversized lines and files, non-UTF-8 bytes, `/dev/zero` and a directory instead of a file. Each one gets exit code 2 and a single error line that never repeats the input.

## Security

- **Bounded input:** at most 64 KB is read (an endless stream is cut off), lines are at most 200 characters, and the file can have at most 30 items. Every number is checked against a range, and only printable ASCII is accepted.
- **Bounded work:** each simulation is capped at 60,000 customers (busy stalls get fewer simulated days), and the search has fixed step limits, so no input can make it run for ever.
- **Exact money:** all amounts are whole cents in `long`, never floating point, so there is no rounding drift and no overflow at these sizes.
- **Errors never repeat the input**, and the program only reads the one file named. It never writes files and uses no network and no shell.

**Known limits, stated honestly:**

- **It is a model.** The payment shares are your estimates, customers are assumed to arrive at random through the day, and a stuck customer is counted as a lost sale (in real life you might round down or take an IOU).
- The search is a careful heuristic, not a proof that no better float exists, though the tests show it beats random alternatives.
- It plans cash only; card payments simply don't count as cash customers.
- No software can promise it is 100% secure; these are the protections in place.
