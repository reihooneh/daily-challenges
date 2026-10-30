# Loadline planner: packs pieces of laundry into the fewest loads, then prints the plan.
# Input (from bin/loadline, already validated), tab separated:
#   M  <machine kg>  <title>
#   I  <item no>  <name>  <count>  <kg each>  <fabric>  <colour>  <max temp>  <hot 0|1>  <bleeds 0|1>
#
# The rules, from typical care labels and machine manuals:
#   - a load runs the gentlest programme any piece in it needs: cotton < synthetic < delicate < wool,
#     and gentler programmes take less: 100%, 50%, 35% and 25% of the drum's rated cotton load;
#   - a load runs at the lowest temperature any piece in it allows;
#   - colours that run into each other stay apart (see ok_colours), and a piece that bleeds only
#     goes with pieces of its own colour;
#   - "hot" pieces (towels, bedding) should get 60 °C when they can.
# Packing is first-fit decreasing by how much of a drum each piece uses, choosing among the loads
# it fits in the one it costs least, then tries to empty the smallest loads into the others.
# A lower bound on the number of loads (by capacity and by colour clashes) shows how close it is.

BEGIN { FS = "\t"; split("cotton synthetic delicate wool", FAB, " "); MAX_EXACT = 18; NODE_CAP = 400000 }

# Depth-first search for the fewest loads (used for small baskets). Unit ORD[i] goes into each
# open load it fits, or a new load if that could still beat BEST.
function dfs(i,    p, l, k) {
  if (++NODES > NODE_CAP) return
  if (NL >= BEST) return
  if (i > NP) {
    BEST = NL; FOUND = 1
    for (l = 1; l <= NL; l++) for (k = 1; k <= LN[l]; k++) BA[L[l, k]] = l
    return
  }
  p = ORD[i]
  for (l = 1; l <= NL; l++) {
    if (!fits(p, l)) continue
    add(p, l); dfs(i + 1); LN[l]--; refresh(l)
    if (NODES > NODE_CAP) return
  }
  if (NL + 1 < BEST) { NL++; LN[NL] = 0; refresh(NL); add(p, NL); dfs(i + 1); LN[NL] = 0; NL-- }
}

function fabric_rank(f) { return f == "cotton" ? 1 : f == "synthetic" ? 2 : f == "delicate" ? 3 : 4 }
function share(rank) { return rank == 1 ? 1 : rank == 2 ? 0.5 : rank == 3 ? 0.35 : 0.25 }
function cap(rank) { return MACHINE * share(rank) }

# Which colours may share a drum. Whites only with whites and lights; reds only with reds and darks.
function ok_colours(a, b) {
  if (a == b) return 1
  if ((a == "white" && b == "light") || (a == "light" && b == "white")) return 1
  if ((a == "light" && b == "bright") || (a == "bright" && b == "light")) return 1
  if ((a == "bright" && b == "dark") || (a == "dark" && b == "bright")) return 1
  if ((a == "dark" && b == "red") || (a == "red" && b == "dark")) return 1
  return 0
}

function ok_pieces(p, q) {
  if (!ok_colours(PC[p], PC[q])) return 0
  if ((PB[p] || PB[q]) && PC[p] != PC[q]) return 0
  return 1
}

# Can piece p join load l? Colours and bleeding against every piece already there, then weight
# against the capacity of the programme the load would need.
function fits(p, l,    k, rank) {
  for (k = 1; k <= LN[l]; k++) if (!ok_pieces(p, L[l, k])) return 0
  rank = LR[l] > PR[p] ? LR[l] : PR[p]
  return LW[l] + PW[p] <= cap(rank) + 1e-9
}

# What it costs to put p in l: capacity lost by a gentler programme, and hot pieces kept cooler.
function cost(p, l,    rank, temp, c, k) {
  rank = LR[l] > PR[p] ? LR[l] : PR[p]
  temp = LT[l] < PT[p] ? LT[l] : PT[p]
  c = (cap(LR[l]) - cap(rank)) * 10
  if (PH[p] && temp < 60) c += 3
  for (k = 1; k <= LN[l]; k++) if (PH[L[l, k]] && LT[l] >= 60 && temp < 60) c += 3
  return c - LW[l] * 0.01  # prefer fuller loads (best fit)
}

# How much the care labels lose in a load: hot pieces below 60 C, and capacity given up to a
# gentler programme than the heaviest fabric needs (weighted by what is in the load).
function load_cost(l,    k, c, p) {
  c = 0
  for (k = 1; k <= LN[l]; k++) { p = L[l, k]; if (PH[p] && LT[l] < 60) c += 3 * PN[p]; c += (LR[l] - PR[p]) * PW[p] }
  return c
}
function add_cost(p, l,    before, after) {
  before = load_cost(l); add(p, l); after = load_cost(l)
  LN[l]--; refresh(l)
  return after - before
}

function add(p, l) {
  LN[l]++; L[l, LN[l]] = p; LW[l] += PW[p]
  if (PR[p] > LR[l]) LR[l] = PR[p]
  if (PT[p] < LT[l]) LT[l] = PT[p]
}

function new_load() { NL++; LN[NL] = 0; LW[NL] = 0; LR[NL] = 1; LT[NL] = 90; return NL }

# Rebuilds a load's programme and temperature from its pieces.
function refresh(l,    k, p) {
  LW[l] = 0; LR[l] = 1; LT[l] = 90
  for (k = 1; k <= LN[l]; k++) { p = L[l, k]; LW[l] += PW[p]; if (PR[p] > LR[l]) LR[l] = PR[p]; if (PT[p] < LT[l]) LT[l] = PT[p] }
}

$1 == "M" { MACHINE = $2 + 0; TITLE = $3; next }
$1 == "I" {
  it = $2 + 0; NI = it
  IN[it] = $3; IC[it] = $4 + 0; IW[it] = $5 + 0; IF[it] = $6; ICOL[it] = $7; ITM[it] = $8 + 0; IHOT[it] = $9 + 0; IB[it] = $10 + 0
  TOTAL += IC[it] * IW[it]
  NPIECES += IC[it]
  next
}

END {
  if (NI == 0) exit 2
  # Units: each item goes in whole if one load of its own programme can take it, otherwise in
  # as few equal-sized chunks as fit. Keeping items together keeps the plan easy to follow.
  NP = 0
  for (it = 1; it <= NI; it++) {
    c1 = cap(fabric_rank(IF[it]))
    if (IW[it] > c1 + 1e-9) { TOOBIG[it] = 1; continue }
    per = int(c1 / IW[it] + 1e-9); if (per > IC[it]) per = IC[it]
    chunks = int((IC[it] + per - 1) / per)
    left = IC[it]
    for (ch = 1; ch <= chunks; ch++) {
      n = int(left / (chunks - ch + 1) + 0.999999); left -= n
      NP++
      PI[NP] = it; PN[NP] = n; PW[NP] = n * IW[it]; PR[NP] = fabric_rank(IF[it]); PC[NP] = ICOL[it]; PT[NP] = ITM[it]; PH[NP] = IHOT[it]; PB[NP] = IB[it]
    }
  }

  # Order units by the share of a drum they use, biggest first (insertion sort: POSIX awk has no sort).
  for (p = 1; p <= NP; p++) { ORD[p] = p; SZ[p] = PW[p] / cap(PR[p]) }
  for (i = 2; i <= NP; i++) {
    x = ORD[i]; j = i - 1
    while (j >= 1 && (SZ[ORD[j]] < SZ[x] || (SZ[ORD[j]] == SZ[x] && ORD[j] > x))) { ORD[j + 1] = ORD[j]; j-- }
    ORD[j + 1] = x
  }

  NL = 0
  for (i = 1; i <= NP; i++) {
    p = ORD[i]
    best = 0
    for (l = 1; l <= NL; l++) if (fits(p, l)) { c = cost(p, l); if (!best || c < bestc) { best = l; bestc = c } }
    # Opening a new load costs more than any compromise above.
    if (!best || bestc > 50) best = new_load()
    add(p, best)
  }

  # Improvement: try to empty each load (smallest first) by moving its pieces into the others.
  changed = 1
  while (changed) {
    changed = 0
    for (l = 1; l <= NL && !changed; l++) {
      if (LN[l] == 0) continue
      # Trial: copy the state, move every piece, keep it only if all of them found a home.
      for (m = 1; m <= NL; m++) { SAVE_N[m] = LN[m]; for (k = 1; k <= LN[m]; k++) SAVE[m, k] = L[m, k] }
      n = LN[l]; for (k = 1; k <= n; k++) MOVE[k] = L[l, k]
      LN[l] = 0; refresh(l)
      ok = 1
      for (k = 1; k <= n && ok; k++) {
        p = MOVE[k]; best = 0
        for (m = 1; m <= NL; m++) if (m != l && LN[m] > 0 && fits(p, m)) { c = cost(p, m); if (!best || c < bestc) { best = m; bestc = c } }
        if (best && bestc <= 50) add(p, best); else ok = 0
      }
      if (ok) changed = 1
      else {
        for (m = 1; m <= NL; m++) { LN[m] = SAVE_N[m]; for (k = 1; k <= LN[m]; k++) L[m, k] = SAVE[m, k]; refresh(m) }
      }
    }
  }

  # Exact check for small baskets: a depth-first search over every way to share the units
  # among loads (each unit tries every open load, then one new load), pruned as soon as it can't
  # beat the best so far. If it finds fewer loads than the greedy plan, its plan is used instead.
  used = 0
  for (l = 1; l <= NL; l++) if (LN[l] > 0) used++
  PROVEN = 0
  if (NP <= MAX_EXACT) {
    BEST = used; NODES = 0
    for (l = 1; l <= NL; l++) { SAVE_N[l] = LN[l]; for (k = 1; k <= LN[l]; k++) SAVE[l, k] = L[l, k] }
    SAVE_NL = NL
    for (l = 1; l <= NL; l++) { LN[l] = 0; refresh(l) }
    NL = 0; FOUND = 0
    dfs(1)
    if (NODES <= NODE_CAP) PROVEN = 1
    if (FOUND) {
      for (l = 1; l <= NP; l++) { LN[l] = 0; refresh(l) }
      NL = BEST
      for (l = 1; l <= NL; l++) { LN[l] = 0; refresh(l) }
      for (i = 1; i <= NP; i++) add(ORD[i], BA[ORD[i]])
    } else {
      NL = SAVE_NL
      for (l = 1; l <= NL; l++) { LN[l] = SAVE_N[l]; for (k = 1; k <= LN[l]; k++) L[l, k] = SAVE[l, k]; refresh(l) }
    }
  }

  # Polish: move single units to another load when that keeps the same number of loads but does
  # better by the care labels (hot pieces back at 60 C, gentler programmes avoided).
  for (round_ = 1; round_ <= 20; round_++) {
    moved = 0
    for (l = 1; l <= NL; l++) {
      for (k = 1; k <= LN[l] && LN[l] > 1; k++) {
        p = L[l, k]
        # The load's cost with and without p: how far its temperature and programme are pushed.
        before = load_cost(l)
        for (q = k; q < LN[l]; q++) L[l, q] = L[l, q + 1]
        LN[l]--; refresh(l)
        saved = before - load_cost(l)
        best = 0
        for (m = 1; m <= NL; m++) if (m != l && LN[m] > 0 && fits(p, m)) {
          extra = add_cost(p, m)
          if (extra < saved - 1e-9 && (!best || extra < bestc)) { best = m; bestc = extra }
        }
        if (best) { add(p, best); moved = 1; k-- }
        else {
          for (q = LN[l] + 1; q > k; q--) L[l, q] = L[l, q - 1]
          L[l, k] = p; LN[l]++; refresh(l)
        }
      }
    }
    if (!moved) break
  }

  # Lower bound 1: capacity. Every piece fills at least its weight over its own programme's capacity.
  need = 0
  for (p = 1; p <= NP; p++) need += PW[p] / cap(PR[p])
  lb = int(need - 1e-9) + 1
  # Lower bound 2: colours (and bleeding pieces) that can't share a drum need separate loads:
  # the largest set of pieces that clash pairwise (found exactly over the distinct kinds present).
  nk = 0
  for (p = 1; p <= NP; p++) {
    key = PC[p] SUBSEP PB[p]
    if (!(key in KIND)) { nk++; KIND[key] = nk; KP[nk] = p }
  }
  clique = 0
  for (mask = 1; mask < 2 ^ nk; mask++) {
    size = 0; good = 1
    for (a = 1; a <= nk && good; a++) {
      if (int(mask / 2 ^ (a - 1)) % 2 == 0) continue
      size++
      for (b = a + 1; b <= nk; b++) if (int(mask / 2 ^ (b - 1)) % 2 == 1 && ok_pieces(KP[a], KP[b])) { good = 0; break }
    }
    if (good && size > clique) clique = size
  }
  if (clique > lb) lb = clique

  # ---------- Report ----------
  if (PROVEN) lb = 0
  used = 0
  for (l = 1; l <= NL; l++) if (LN[l] > 0) used++
  printf "LOADLINE  %s (%g kg machine)\n", TITLE, MACHINE
  if (PROVEN) printf "%d pieces, %.1f kg in %d loads: the fewest possible without splitting an item (every way to share them out was checked).\n\n", NPIECES, TOTAL, used
  else printf "%d pieces, %.1f kg in %d loads. No plan can use fewer than %d (by weight and colour clashes alone).\n\n", NPIECES, TOTAL, used, lb
  kwh = 0; shown = 0
  for (l = 1; l <= NL; l++) {
    if (LN[l] == 0) continue
    shown++
    c = cap(LR[l]); fill = int(LW[l] / c * 10 + 0.5); bar = ""
    for (k = 1; k <= 10; k++) bar = bar (k <= fill ? "#" : ".")
    printf "Load %d: %s programme at %d C, %.1f of %.1f kg  %s\n", shown, FAB[LR[l]], LT[l], LW[l], c, bar
    kwh += LT[l] >= 90 ? 1.8 : LT[l] >= 60 ? 1.1 : LT[l] >= 40 ? 0.7 : LT[l] >= 30 ? 0.5 : 0.35
    # Count pieces of each item in this load, in item order.
    for (it = 1; it <= NI; it++) CNT[it] = 0
    for (k = 1; k <= LN[l]; k++) CNT[PI[L[l, k]]] += PN[L[l, k]]
    for (it = 1; it <= NI; it++) {
      if (!CNT[it]) continue
      note = ""
      if (IHOT[it] && LT[l] < 60) note = "  (wanted 60 C)"
      if (IB[it]) note = note "  (may bleed: only " ICOL[it] " with it)"
      printf "  %3d x %s  [%s, %s, up to %d C]%s\n", CNT[it], IN[it], IF[it], ICOL[it], ITM[it], note
      if (CNT[it] < IC[it]) SPLIT[it] = 1
    }
    print ""
  }
  printf "About %.1f kWh in all (rough figures per wash by temperature).\n", kwh
  for (it = 1; it <= NI; it++) if (TOOBIG[it]) printf "Note: %s is too heavy for a %s programme in this machine; take it to a laundrette.\n", IN[it], IF[it]
  for (it = 1; it <= NI; it++) if (SPLIT[it]) printf "Note: the %s are split across loads.\n", IN[it]
  if (!PROVEN && used > lb) print "The bound ignores how programmes and temperatures combine, so the true minimum may be above it."
  print "Always follow the care label on the garment itself."
}
