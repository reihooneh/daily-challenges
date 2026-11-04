// Playing a ringer's bells through the piece, and choosing the split of bells between ringers.
#include <algorithm>
#include <cmath>
#include <map>
#include <sstream>

#include "bellshare.hpp"

namespace bellshare {

std::vector<int> bellsUsed(const Piece& p) {
  std::vector<int> all;
  for (const auto& c : p.chords) all.insert(all.end(), c.notes.begin(), c.notes.end());
  std::sort(all.begin(), all.end());
  all.erase(std::unique(all.begin(), all.end()), all.end());
  return all;
}

std::string where(const Piece& p, double time) {
  const int measure = static_cast<int>(std::floor(time / p.beatsPerMeasure + 1e-9)) + 1;
  const double beat = time - (measure - 1) * p.beatsPerMeasure + 1;
  std::ostringstream o;
  o << 'm' << measure << ':' << beat;
  return o.str();
}

Load play(const Piece& p, const std::vector<int>& bells) {
  Load load;
  // When each of these bells is next needed, for Belady's rule.
  std::map<int, std::vector<double>> uses;
  std::vector<std::pair<double, std::vector<int>>> events;
  for (const auto& c : p.chords) {
    std::vector<int> need;
    for (int n : c.notes)
      if (std::binary_search(bells.begin(), bells.end(), n)) need.push_back(n);
    if (need.empty()) continue;
    for (int n : need) uses[n].push_back(c.time);
    load.rung += static_cast<int>(need.size());
    if (need.size() > 2) {
      if (load.possible) load.firstClash = c.time;
      load.possible = false;
      ++load.clashes;
      need.resize(2);  // play on with the first two, so the rest of the piece is still judged
    }
    events.emplace_back(c.time, need);
  }
  auto nextUse = [&](int bell, double after) {
    const auto& v = uses[bell];
    const auto it = std::upper_bound(v.begin(), v.end(), after);
    return it == v.end() ? INFINITY : *it;
  };

  struct Hand {
    int bell = -1;
    double last = -std::numeric_limits<double>::infinity();  // when this hand last rang
  };
  Hand hands[2];
  for (const auto& [t, need] : events) {
    for (int n : need) {
      if (hands[0].bell == n || hands[1].bell == n) continue;
      // An empty hand picks the bell up before the piece needs it: free.
      int slot = hands[0].bell < 0 ? 0 : hands[1].bell < 0 ? 1 : -1;
      if (slot < 0) {
        // Never put down a bell that this same chord needs; otherwise the one needed last.
        const bool keep0 = std::find(need.begin(), need.end(), hands[0].bell) != need.end();
        const bool keep1 = std::find(need.begin(), need.end(), hands[1].bell) != need.end();
        if (keep0) slot = 1;
        else if (keep1) slot = 0;
        else {
          // Ties (neither needed again, say) go to the hand that has been free longest.
          const double n0 = nextUse(hands[0].bell, t), n1 = nextUse(hands[1].bell, t);
          slot = n0 > n1 ? 0 : n1 > n0 ? 1 : (hands[0].last <= hands[1].last ? 0 : 1);
        }
        Change ch;
        ch.time = t;
        ch.down = hands[slot].bell;
        ch.up = n;
        ch.room = t - hands[slot].last;
        ch.tight = ch.room < p.swapBeats;
        if (ch.tight) ++load.tight;
        load.changes.push_back(ch);
      }
      hands[slot].bell = n;
    }
    for (auto& h : hands)
      if (std::find(need.begin(), need.end(), h.bell) != need.end()) h.last = t;
  }
  return load;
}

double cost(const Load& l) {
  return kImpossible * l.clashes + static_cast<double>(l.changes.size()) + kTightWeight * l.tight;
}

namespace {

double groupCost(const Piece& p, const std::vector<int>& bells, Load* out = nullptr) {
  Load l = play(p, bells);
  double c = cost(l);
  const auto extra = static_cast<int>(bells.size()) - p.maxBells;
  if (extra > 0) c += kImpossible * extra;
  if (out) *out = std::move(l);
  return c;
}

}  // namespace

Assignment evaluate(const Piece& p, const std::vector<std::vector<int>>& runs) {
  Assignment a;
  a.ringers = runs;
  a.cost = 0;
  for (const auto& r : runs) {
    Load l;
    a.cost += groupCost(p, r, &l);
    if (!l.possible || static_cast<int>(r.size()) > p.maxBells) a.possible = false;
    a.loads.push_back(std::move(l));
  }
  return a;
}

Assignment best(const Piece& p) {
  const std::vector<int> bells = bellsUsed(p);
  const int m = static_cast<int>(bells.size());
  const int r = std::min(p.ringers, m);
  // cost[i][j]: one ringer with bells i..j-1.
  std::vector<std::vector<double>> run(static_cast<std::size_t>(m + 1), std::vector<double>(static_cast<std::size_t>(m + 1), INFINITY));
  for (int i = 0; i < m; ++i)
    for (int j = i + 1; j <= m; ++j)
      run[static_cast<std::size_t>(i)][static_cast<std::size_t>(j)] =
          groupCost(p, std::vector<int>(bells.begin() + i, bells.begin() + j));
  // best[k][j]: the first j bells shared by k ringers, each with at least one bell. Ties go to
  // the plan whose busiest ringer has the fewest bells.
  struct Cell {
    double cost = INFINITY;
    int most = 1 << 20;
    int from = -1;
  };
  std::vector<std::vector<Cell>> dp(static_cast<std::size_t>(r + 1), std::vector<Cell>(static_cast<std::size_t>(m + 1)));
  dp[0][0] = {0, 0, -1};
  for (int k = 1; k <= r; ++k) {
    for (int j = k; j <= m; ++j) {
      Cell& cell = dp[static_cast<std::size_t>(k)][static_cast<std::size_t>(j)];
      for (int i = k - 1; i < j; ++i) {
        const Cell& prev = dp[static_cast<std::size_t>(k - 1)][static_cast<std::size_t>(i)];
        if (!std::isfinite(prev.cost)) continue;
        const double c = prev.cost + run[static_cast<std::size_t>(i)][static_cast<std::size_t>(j)];
        const int most = std::max(prev.most, j - i);
        if (c < cell.cost - 1e-9 || (std::abs(c - cell.cost) <= 1e-9 && most < cell.most)) cell = {c, most, i};
      }
    }
  }
  std::vector<std::vector<int>> runs;
  for (int k = r, j = m; k > 0; --k) {
    const int i = dp[static_cast<std::size_t>(k)][static_cast<std::size_t>(j)].from;
    runs.emplace_back(bells.begin() + i, bells.begin() + j);
    j = i;
  }
  std::reverse(runs.begin(), runs.end());
  return evaluate(p, runs);
}

Assignment equalSplit(const Piece& p) {
  const std::vector<int> bells = bellsUsed(p);
  const int m = static_cast<int>(bells.size());
  const int r = std::min(p.ringers, m);
  std::vector<std::vector<int>> runs;
  int at = 0;
  for (int k = 0; k < r; ++k) {
    const int size = m / r + (k < m % r ? 1 : 0);
    runs.emplace_back(bells.begin() + at, bells.begin() + at + size);
    at += size;
  }
  return evaluate(p, runs);
}

}  // namespace bellshare
