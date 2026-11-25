# Dawnlist planner: reads a big-day file on standard input, finds the order and timing of stops
# that maximise the expected number of species seen, and prints the day.
#
# Variables (set with -v by bin/dawnlist): exact=1 turns the bound off (for tests), budget caps
# how many partial routes are weighed, machine=1 prints "expected route" only (for tests).

function fail(msg) { printf "dawnlist: line %d: %s\n", NR, msg > "/dev/stderr"; failed = 1; exit 2 }
function failall(msg) { printf "dawnlist: %s\n", msg > "/dev/stderr"; failed = 1; exit 2 }

function clock(s,   h, m) {
  if (s !~ /^([01][0-9]|2[0-3]):[0-5][0-9]$/) return -1
  h = substr(s, 1, 2) + 0; m = substr(s, 4, 2) + 0
  return h * 60 + m
}
function wrap(text, width,   w, n, i, line, outp) {
  n = split(text, w, " "); line = ""; outp = ""
  for (i = 1; i <= n; i++) {
    if (line != "" && length(line) + 1 + length(w[i]) > width) { outp = outp line "\n"; line = "  " w[i] }
    else line = (line == "" ? w[i] : line " " w[i])
  }
  return outp line
}
function hhmm(t) { return sprintf("%02d:%02d", int(t / 60), t % 60) }
function rest(from,   i, s) { s = $from; for (i = from + 1; i <= NF; i++) s = s " " $i; return s }
function needid(s, what) { if (s !~ /^[a-z][a-z0-9-]*$/ || length(s) > 20) fail(what " must be a short id like lagoon or north-heath") }
function needname(s, what) { if (s !~ /^[A-Za-z0-9][A-Za-z0-9 .,'()-]*$/ || length(s) > 40) fail(what " must be a name of up to 40 letters, digits and simple punctuation") }
function needint(s, lo, hi, what) {
  if (s !~ /^[0-9]+$/ || length(s) > 4 || s + 0 < lo || s + 0 > hi) fail(what " must be a whole number from " lo " to " hi)
  return s + 0
}

BEGIN {
  MAXSITES = 12; MAXSPECIES = 120; MAXBIRDLINES = 600; MAXTRAVEL = 200
  if (budget == "") budget = 150000
  nsites = 0; nspecies = 0; nbird = 0; ntravel = 0; startid = ""; endt = -1
}

{
  if (length($0) > 200) fail("lines are at most 200 characters")
  if ($0 ~ /[^ -~\t]/) fail("only plain printable text is allowed (no control characters)")
  sub(/#.*/, "")
  if (NF == 0) next
  kind = $1
  if (kind == "start") {
    if (NF != 3) fail("start ID HH:MM, for example: start home 05:00")
    if (startid != "") fail("only one start line")
    needid($2, "the start place"); startid = $2
    startt = clock($3); if (startt < 0) fail("the start time is HH:MM")
  } else if (kind == "end") {
    if (NF != 2) fail("end HH:MM")
    if (endt >= 0) fail("only one end line")
    endt = clock($2); if (endt < 0) fail("the end time is HH:MM")
  } else if (kind == "site") {
    if (NF < 4) fail("site ID MINUTES NAME, for example: site lagoon 45 Long Reef lagoon")
    needid($2, "a site id")
    if ($2 in siteidx) fail("site " $2 " is listed twice")
    if (++nsites > MAXSITES) fail("at most " MAXSITES " sites (the search is exact)")
    siteidx[$2] = nsites; sid[nsites] = $2
    stay[nsites] = needint($3, 5, 480, "minutes at a site")
    sname[nsites] = rest(4); needname(sname[nsites], "a site name")
  } else if (kind == "travel") {
    if (NF != 4) fail("travel FROM TO MINUTES")
    needid($2, "a place id"); needid($3, "a place id")
    if ($2 == $3) fail("travel needs two different places")
    if (++ntravel > MAXTRAVEL) fail("at most " MAXTRAVEL " travel lines")
    tv = needint($4, 1, 600, "travel minutes")
    tfrom[ntravel] = $2; tto[ntravel] = $3; tmin[ntravel] = tv; tline[ntravel] = NR
  } else if (kind == "bird") {
    if (NF < 4) fail("bird SITE CHANCE [HH:MM-HH:MM] NAME, for example: bird lagoon 0.6 05:00-07:00 Australasian Bittern")
    needid($2, "a site id")
    if ($3 !~ /^(0\.[0-9]{1,3}|1(\.0{1,3})?)$/ || $3 + 0 <= 0) fail("the chance of seeing a bird is a number above 0 and at most 1, like 0.35")
    from = 0; to = 1440; at = 4
    if ($4 ~ /^[0-9:]+-[0-9:]+$/) {
      from = clock(substr($4, 1, 5)); to = clock(substr($4, 7))
      if (length($4) != 11 || from < 0 || to < 0 || from >= to) fail("a time window is HH:MM-HH:MM, earlier time first")
      at = 5
    }
    if (NF < at) fail("the bird needs a name")
    nm = rest(at); needname(nm, "a bird name")
    if (!(nm in spidx)) {
      if (++nspecies > MAXSPECIES) fail("at most " MAXSPECIES " species")
      spidx[nm] = nspecies; spname[nspecies] = nm
    }
    if (++nbird > MAXBIRDLINES) fail("at most " MAXBIRDLINES " bird lines")
    bsite[nbird] = $2; bsp[nbird] = spidx[nm]; bp[nbird] = $3 + 0; bfrom[nbird] = from; bto[nbird] = to; bline[nbird] = NR
  } else {
    fail("lines start with start, end, site, travel or bird (not " substr(kind, 1, 20) ")")
  }
}

END {
  if (failed) exit 2
  if (startid == "") failall("say where and when the day starts: start home 05:00")
  if (endt < 0) failall("say when the day ends: end 18:30")
  if (endt <= startt) failall("the day must end after it starts")
  if (nsites == 0) failall("list at least one site")
  if (startid in siteidx) failall("the start place is where you set out from, not a site to bird")
  if (nspecies == 0) failall("list at least one bird")
  # Places: 0 is the start, 1..nsites the sites.
  for (i = 1; i <= ntravel; i++) {
    a = (tfrom[i] == startid) ? 0 : ((tfrom[i] in siteidx) ? siteidx[tfrom[i]] : -1)
    b = (tto[i] == startid) ? 0 : ((tto[i] in siteidx) ? siteidx[tto[i]] : -1)
    if (a < 0 || b < 0) { NR = tline[i]; fail("travel between unknown places") }
    if ((a, b) in tt) { NR = tline[i]; fail("travel between these places is given twice") }
    tt[a, b] = tmin[i]; tt[b, a] = tmin[i]
  }
  for (i = 1; i <= nbird; i++) {
    if (!(bsite[i] in siteidx)) { NR = bline[i]; fail("bird at unknown site " bsite[i]) }
    k = siteidx[bsite[i]]; s = bsp[i]
    if (!((s, k) in has)) { has[s, k] = 1; nat[k]++; at_sp[k, nat[k]] = s }
    nl[s, k]++; lp[s, k, nl[s, k]] = bp[i]; lf[s, k, nl[s, k]] = bfrom[i]; lt[s, k, nl[s, k]] = bto[i]
    if (bp[i] > maxp[s, k]) maxp[s, k] = bp[i]
    # Window openings are times worth waiting for.
    if (bfrom[i] > 0) { if (!((k, bfrom[i]) in isopen)) { isopen[k, bfrom[i]] = 1; nopen[k]++; opens[k, nopen[k]] = bfrom[i] } }
  }
  for (s = 1; s <= nspecies; s++) miss[s] = 1
  # Shortest drive between every pair of places, through any others (Floyd-Warshall): the bound
  # must not miss a site that is only reachable the long way round.
  for (a = 0; a <= nsites; a++) for (b = 0; b <= nsites; b++) dist[a, b] = (a == b) ? 0 : (((a, b) in tt) ? tt[a, b] : 1e9)
  for (m = 0; m <= nsites; m++) for (a = 0; a <= nsites; a++) for (b = 0; b <= nsites; b++)
    if (dist[a, m] + dist[m, b] < dist[a, b]) dist[a, b] = dist[a, m] + dist[m, b]

  # Start from the hurried birder's day, so even a search cut short is never worse than it.
  best = greedy(); bestn = gn; bestend = startt
  for (d = 1; d <= gn; d++) { broute[d] = gk[d]; btime[d] = gt[d]; bgain[d] = gg[d]; barr[d] = ga[d]; bestend = gt[d] + stay[gk[d]] }
  nodes = 0; complete = 1; depth = 0
  search(0, startt, 0)

  if (machine) {
    r = ""; for (d = 1; d <= bestn; d++) r = r (d > 1 ? "," : "") sid[broute[d]] "@" hhmm(btime[d])
    printf "%.6f %s %d\n", best, (r == "" ? "-" : r), complete
    exit 0
  }
  report()
}

# Chance of seeing species s at site k on a visit that starts at time t: the best window that
# covers t, otherwise the all-day chance.
function chance(s, k, t,   j, p, wp, dp) {
  wp = -1; dp = 0
  for (j = 1; j <= nl[s, k]; j++) {
    p = lp[s, k, j]
    if (lf[s, k, j] == 0 && lt[s, k, j] == 1440) { if (p > dp) dp = p }
    else if (t >= lf[s, k, j] && t < lt[s, k, j]) { if (p > wp) wp = p }
  }
  return wp >= 0 ? wp : dp
}

# Visit site k starting at time t: update the miss chances, return the gain, remember what changed.
function visit(k, t, d,   i, s, p, g) {
  g = 0
  for (i = 1; i <= nat[k]; i++) {
    s = at_sp[k, i]; p = chance(s, k, t)
    saved[d, i] = miss[s]
    g += miss[s] * p; miss[s] *= (1 - p)
  }
  return g
}
function unvisit(k, d,   i) { for (i = 1; i <= nat[k]; i++) miss[at_sp[k, i]] = saved[d, i] }

# The most the rest of the day could add: every site still within reach (by the shortest way
# there) visited at its best time. No real route can do better, so pruning on it loses nothing.
function bound(cur, t,   k, i, s, ub) {
  split("", q)
  for (k = 1; k <= nsites; k++) {
    if (used[k] || t + dist[cur, k] + stay[k] > endt) continue
    for (i = 1; i <= nat[k]; i++) {
      s = at_sp[k, i]
      if (!(s in q)) q[s] = 1
      q[s] *= (1 - maxp[s, k])
    }
  }
  ub = 0
  for (s in q) ub += miss[s] * (1 - q[s])
  return ub
}

function gain(k, t,   i, s, g) {
  g = 0
  for (i = 1; i <= nat[k]; i++) { s = at_sp[k, i]; g += miss[s] * chance(s, k, t) }
  return g
}

function search(cur, t, ev,   k, arr, j, st, g, n, ck, cs, cg, i, tk, ts, tg) {
  if (++nodes > budget) { complete = 0; return }
  if (ev > best + 1e-9 || (ev > best - 1e-9 && t < bestend)) {
    best = ev; bestend = t; bestn = depth
    for (j = 1; j <= depth; j++) { broute[j] = route[j]; btime[j] = rtime[j]; bgain[j] = rgain[j]; barr[j] = rarr[j] }
  }
  if (!exact && ev + bound(cur, t) <= best + 1e-9) return
  # Every next stop: start on arrival, or wait for one of its windows to open.
  n = 0
  for (k = 1; k <= nsites; k++) {
    if (used[k] || !((cur, k) in tt)) continue
    arr = t + tt[cur, k]
    if (arr + stay[k] > endt) continue
    n++; ck[n] = k; cs[n] = arr
    for (j = 1; j <= nopen[k]; j++) if (opens[k, j] > arr && opens[k, j] + stay[k] <= endt) { n++; ck[n] = k; cs[n] = opens[k, j] }
  }
  # Most species per minute first, so good days are found early and the bound cuts more.
  for (i = 1; i <= n; i++) cg[i] = gain(ck[i], cs[i]) / (cs[i] - t + stay[ck[i]])
  for (i = 2; i <= n; i++) {
    tk = ck[i]; ts = cs[i]; tg = cg[i]
    for (j = i - 1; j >= 1 && cg[j] < tg; j--) { ck[j + 1] = ck[j]; cs[j + 1] = cs[j]; cg[j + 1] = cg[j] }
    ck[j + 1] = tk; cs[j + 1] = ts; cg[j + 1] = tg
  }
  for (i = 1; i <= n; i++) {
    k = ck[i]; st = cs[i]
    depth++; used[k] = 1; route[depth] = k; rtime[depth] = st; rarr[depth] = t + tt[cur, k]
    g = visit(k, st, depth); rgain[depth] = g
    search(k, st + stay[k], ev + g)
    unvisit(k, depth); used[k] = 0; depth--
    if (!complete) return
  }
}

# The plan a hurried birder might make: always the stop with the most expected species per minute.
function greedy(   cur, t, ev, k, bk, bt, br, arr, g, r, i, d) {
  cur = 0; t = startt; ev = 0; d = 0; split("", gused)
  while (1) {
    bk = 0; br = 0
    for (k = 1; k <= nsites; k++) {
      if (gused[k] || !((cur, k) in tt)) continue
      arr = t + tt[cur, k]; if (arr + stay[k] > endt) continue
      g = 0; for (i = 1; i <= nat[k]; i++) g += miss[at_sp[k, i]] * chance(at_sp[k, i], k, arr)
      r = g / (tt[cur, k] + stay[k])
      if (r > br) { br = r; bk = k; bt = arr }
    }
    if (!bk) break
    gused[bk] = 1; d++; ga[d] = t + tt[cur, bk]; gt[d] = bt; gg[d] = visit(bk, bt, 100 + d); ev += gg[d]; gk[d] = bk
    cur = bk; t = bt + stay[bk]
  }
  gn = d
  for (; d > 0; d--) unvisit(gk[d], 100 + d)
  return ev
}

function report(   d, k, s, i, tot, gr, order, n, tmp, j, sure, drive, out, nout) {
  printf "Dawnlist: %d sites, %d species, %s to %s from %s\n\n", nsites, nspecies, hhmm(startt), hhmm(endt), startid
  if (bestn == 0) { print "No site can be reached and birded before the day ends. Start earlier or end later."; return }
  printf "Expected species: %.1f of %d", best, nspecies
  printf " (%s, %d partial routes weighed)\n\n", complete ? "the best possible order and timing" : "search stopped at its limit, the best found", nodes
  cur = 0
  for (d = 1; d <= bestn; d++) {
    k = broute[d]
    drive = tt[(d == 1 ? 0 : broute[d - 1]), k]
    printf "  %s-%s  %-22s %3d min drive  %-12s +%.1f species\n", hhmm(btime[d]), hhmm(btime[d] + stay[k]), sname[k], drive,
      (btime[d] > barr[d] ? sprintf("wait %d min", btime[d] - barr[d]) : ""), bgain[d]
  }
  # Replay the plan to get each species' chance.
  for (s = 1; s <= nspecies; s++) miss[s] = 1
  for (d = 1; d <= bestn; d++) visit(broute[d], btime[d], 200 + d)
  for (s = 1; s <= nspecies; s++) seen[s] = 1 - miss[s]
  for (d = bestn; d >= 1; d--) unvisit(broute[d], 200 + d)
  gr = greedy()
  printf "\nThe stop with the most species per minute, every time, would expect %.1f.\n", gr
  # Each stop's worth: the plan without it.
  print "\nWhat each stop adds to the day (the plan without it):"
  for (d = 1; d <= bestn; d++) {
    for (s = 1; s <= nspecies; s++) miss[s] = 1
    tot = 0
    for (j = 1; j <= bestn; j++) if (j != d) tot += visit(broute[j], btime[j], 300 + j)
    for (j = bestn; j >= 1; j--) if (j != d) unvisit(broute[j], 300 + j)
    printf "  %-22s %.1f species\n", sname[broute[d]], best - tot
  }
  # The long shots: lowest chances, ignoring birds the route never gives a chance at.
  n = 0
  for (s = 1; s <= nspecies; s++) { order[++n] = s }
  for (i = 2; i <= n; i++) { tmp = order[i]; for (j = i - 1; j >= 1 && seen[order[j]] > seen[tmp]; j--) order[j + 1] = order[j]; order[j + 1] = tmp }
  out = ""; nout = 0
  for (i = 1; i <= n; i++) if (seen[order[i]] < 0.0005) { out = out (nout++ ? ", " : "") spname[order[i]] }
  if (nout) printf "\n%s\n", wrap("No chance on this route (no stop has them at those times): " out ".", 96)
  print "\nLong shots on this route:"
  for (i = nout + 1; i <= n && i <= nout + 5; i++) printf "  %-26s %2.0f%% chance\n", spname[order[i]], 100 * seen[order[i]]
  sure = 0; for (s = 1; s <= nspecies; s++) if (seen[s] >= 0.9) sure++
  printf "\n%d species are 90%% likely or better.\n", sure
}
