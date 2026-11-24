# Crownwind

**When to wind which watch, so nothing in your collection stops, with the fewest winding sessions and the fewest turns of each crown.**

A manual-wind watch runs a day and a half to eight days on a full wind. Let one stop and you reset the
time; let an annual calendar or a moon phase stop and you're setting complications with a pin. With a
few watches of different reserves, plus automatics that wind themselves on the days you wear them,
"wind everything every morning" wears crowns for nothing and still misses the watch you forgot.
Crownwind takes the times you're actually home and plans the fewest sessions that keep every watch
running, then which watches need a turn at each one.

## Features

- Manual and automatic watches; an automatic worn before it stops is full when you take it off.
- A safety margin on every power reserve (10 % by default), and "may stop" for watches you don't mind.
- **Fewest sessions**, proven by an exchange argument and checked against a brute force over every
  set of slots; then **fewest windings** per watch, also checked by brute force.
- Watches no slot can save are reported with when they'll stop.

## Example

```
$ node src/cli.js examples/collection.json
6 watches over 14 days, keeping a 10 % reserve margin.
10 winding sessions keep 5 of them running; 33 crown windings in all.

  Mon day 1 07:15   wind Calatrava, Speedmaster
  Tue day 2 21:30   wind Calatrava, Speedmaster, Lange 1
  Thu day 4 07:15   wind Calatrava, Speedmaster, Lange 1, 8-day Panerai
  Fri day 5 21:30   wind Calatrava, Speedmaster, Lange 1, Annual calendar
  Sun day 7 13:00   wind Calatrava, Speedmaster, Lange 1, Annual calendar
  Mon day 8 21:30   wind Calatrava, Speedmaster, Lange 1
  Wed day 10 07:15   wind Calatrava, Speedmaster, Lange 1, 8-day Panerai
  Thu day 11 21:30   wind Calatrava, Speedmaster, Lange 1
  Sat day 13 13:00   wind Calatrava, Speedmaster, Lange 1, Annual calendar
  Sun day 14 21:30   wind Calatrava, Annual calendar

Allowed to stop (not planned): Seiko diver.

Per watch:
  Calatrava                manual    reserve   44 h   wound 10 times
  Speedmaster              manual    reserve   50 h   wound 9 times
  Lange 1                  manual    reserve   72 h   wound 8 times
  8-day Panerai            manual    reserve  192 h   wound 2 times
  Annual calendar          automatic reserve   45 h   wound 4 times
```

A collection is JSON: when the plan starts, how many days, the margin, the times you can wind (by
weekday), and each watch's reserve in hours, how much it has left now, manual or automatic, when you
wear it, and whether it may stop. See `examples/collection.json`.

## Run and test

```sh
node src/cli.js examples/collection.json
npm test      # node:test, no dependencies
```

Node 20 or later, no packages.

## Security

- The collection must be a regular file under 64 KB, parsed with `JSON.parse` only.
- Every field is checked: names match a short allow-list pattern (no markup or terminal escapes in
  the report), times must be `HH:MM`, weekdays 0 to 6, reserves 6 to 2000 hours, at most 60 days,
  60 watches, 40 slot groups and 20 wear patterns per watch, so the plan's size is bounded.
- No dependencies, so nothing to audit or update; no `eval`, no network, no file writes.
- Known limits: power reserves vary with a watch's age and service; leave the margin on.
