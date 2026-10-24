#include "cutting.hpp"

#include <algorithm>
#include <cmath>
#include <map>
#include <numeric>
#include <optional>
#include <unordered_map>

namespace weftwise {
namespace {

// One way a piece can lie in a strip.
struct Option {
  Len height;  // across the strip (the strip must be at least this tall)
  Len length;  // along the strip
  bool turned;
};

// A kind of piece that goes into crosswise strips.
struct Item {
  std::string name;
  std::vector<Option> options;
  long long area = 0;
  int demand = 0;
  Len minHeight = 0;
};

// The best way to lay an item in a strip of height h: the shortest length along the strip.
// A length of 0 means the item can't go in a strip that low.
Option bestAt(const Item& it, Len h) {
  Option best{0, 0, false};
  for (const auto& o : it.options) {
    if (o.height > h) continue;
    if (best.length == 0 || o.length < best.length || (o.length == best.length && o.height < best.height)) best = o;
  }
  return best;
}

bool fitsAt(const Item& it, Len h) { return bestAt(it, h).length > 0; }

struct Pattern {
  Len height = 0;
  std::vector<int> counts;
};

Len ceilDiv(long long a, long long b) { return static_cast<Len>((a + b - 1) / b); }

class Solver {
 public:
  Solver(std::vector<Item> items, Len width, SearchLimits limits)
      : items_(std::move(items)), width_(width), limits_(limits) {
    for (const auto& it : items_) {
      for (const auto& o : it.options) heights_.push_back(o.height);
    }
    std::sort(heights_.begin(), heights_.end());
    heights_.erase(std::unique(heights_.begin(), heights_.end()), heights_.end());
  }

  Len lowerBound(const std::vector<int>& rem) const {
    long long area = 0;
    Len tallest = 0;
    for (std::size_t i = 0; i < items_.size(); ++i) {
      if (rem[i] == 0) continue;
      area += items_[i].area * rem[i];
      tallest = std::max(tallest, items_[i].minHeight);
    }
    Len bound = std::max(ceilDiv(area, width_), tallest);
    if (!prices_.empty()) {
      double priced = 0;
      for (std::size_t i = 0; i < items_.size(); ++i) priced += prices_[i] * rem[i];
      bound = std::max(bound, static_cast<Len>(std::ceil(priced - 1e-6)));
    }
    return bound;
  }

  // Prices for each kind of piece from the linear-programming relaxation (Gilmore and Gomory).
  // Any prices where no strip is "worth" more than its height give a valid lower bound on the
  // total length: sum of demand x price. Solved by the revised simplex method, then scaled down
  // so the bound holds even if rounding left the prices slightly too high.
  void price(const std::vector<int>& demand) {
    const std::size_t m = items_.size();
    struct Col { std::vector<double> a; double c; };
    std::vector<Col> cols;
    for (const auto& p : patterns_) {
      Col col{std::vector<double>(m), static_cast<double>(p.height)};
      for (std::size_t i = 0; i < m; ++i) col.a[i] = p.counts[i];
      cols.push_back(col);
    }
    std::vector<std::size_t> basis;
    std::vector<std::vector<double>> inv(m, std::vector<double>(m, 0.0));
    std::vector<double> x(m);
    for (std::size_t i = 0; i < m; ++i) {  // start from strips holding one kind of piece each
      double bestN = 0, bestH = 0;
      for (const auto& o : items_[i].options) {
        const double n = static_cast<double>(std::min<Len>(demand[i], width_ / o.length));
        if (bestN == 0 || n / static_cast<double>(o.height) > bestN / bestH) { bestN = n; bestH = static_cast<double>(o.height); }
      }
      Col col{std::vector<double>(m, 0.0), bestH};
      col.a[i] = bestN;
      basis.push_back(cols.size());
      cols.push_back(col);
      inv[i][i] = 1.0 / bestN;
      x[i] = demand[i] / bestN;
    }
    for (std::size_t i = 0; i < m; ++i) {  // surplus: cutting more than needed is allowed
      Col col{std::vector<double>(m, 0.0), 0.0};
      col.a[i] = -1;
      cols.push_back(col);
    }
    std::vector<double> y(m);
    for (int iter = 0; iter < 2000; ++iter) {
      for (std::size_t j = 0; j < m; ++j) {
        y[j] = 0;
        for (std::size_t k = 0; k < m; ++k) y[j] += cols[basis[k]].c * inv[k][j];
      }
      std::size_t enter = cols.size();
      double bestRc = -1e-9;
      for (std::size_t c = 0; c < cols.size(); ++c) {
        double rc = cols[c].c;
        for (std::size_t i = 0; i < m; ++i) rc -= y[i] * cols[c].a[i];
        if (rc < bestRc) { bestRc = rc; enter = c; }
      }
      if (enter == cols.size()) break;
      std::vector<double> u(m, 0.0);
      for (std::size_t k = 0; k < m; ++k)
        for (std::size_t i = 0; i < m; ++i) u[k] += inv[k][i] * cols[enter].a[i];
      std::size_t row = m;
      double ratio = 0;
      for (std::size_t k = 0; k < m; ++k) {
        if (u[k] > 1e-12 && (row == m || x[k] / u[k] < ratio)) { row = k; ratio = x[k] / u[k]; }
      }
      if (row == m) break;
      const double pivot = u[row];
      for (auto& v : inv[row]) v /= pivot;
      x[row] /= pivot;
      for (std::size_t k = 0; k < m; ++k) {
        if (k == row || u[k] == 0) continue;
        for (std::size_t i = 0; i < m; ++i) inv[k][i] -= u[k] * inv[row][i];
        x[k] -= u[k] * x[row];
      }
      basis[row] = enter;
    }
    // Make the prices safe: none negative, and no strip worth more than its height.
    for (auto& v : y) v = std::max(0.0, v);
    double worst = 1.0;
    for (const auto& p : patterns_) {
      double worth = 0;
      for (std::size_t i = 0; i < m; ++i) worth += y[i] * p.counts[i];
      worst = std::max(worst, worth / static_cast<double>(p.height));
    }
    for (auto& v : y) v = v / worst * (1 - 1e-9);
    prices_ = y;
  }

  // Fills a strip of each candidate height greedily and keeps the one that wastes least.
  std::vector<Pattern> greedy(std::vector<int> rem) const {
    std::vector<Pattern> plan;
    while (std::any_of(rem.begin(), rem.end(), [](int r) { return r > 0; })) {
      std::optional<Pattern> best;
      double bestScore = -1;
      for (Len h : heights_) {
        Pattern p{h, std::vector<int>(items_.size(), 0)};
        std::vector<std::size_t> order;
        for (std::size_t i = 0; i < items_.size(); ++i) if (rem[i] > 0 && fitsAt(items_[i], h)) order.push_back(i);
        std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
          return bestAt(items_[a], h).height > bestAt(items_[b], h).height ||
                 (bestAt(items_[a], h).height == bestAt(items_[b], h).height && items_[a].area > items_[b].area);
        });
        Len left = width_;
        long long covered = 0;
        for (auto i : order) {
          Len len = bestAt(items_[i], h).length;
          int n = static_cast<int>(std::min<Len>(rem[i], left / len));
          p.counts[i] = n;
          left -= n * len;
          covered += items_[i].area * n;
        }
        if (covered == 0) continue;
        double score = static_cast<double>(covered) / static_cast<double>(h);
        if (score > bestScore) { bestScore = score; best = p; }
      }
      if (!best) break;  // can't happen: every piece fits a strip of its own height
      for (std::size_t i = 0; i < rem.size(); ++i) rem[i] -= std::min(rem[i], best->counts[i]);
      plan.push_back(*best);
    }
    return plan;
  }

  // Every maximal way to fill a strip of each height. False if there are too many to search.
  bool enumerate() {
    for (Len h : heights_) {
      std::vector<std::size_t> eligible;
      for (std::size_t i = 0; i < items_.size(); ++i) if (fitsAt(items_[i], h)) eligible.push_back(i);
      Pattern p{h, std::vector<int>(items_.size(), 0)};
      if (!fill(eligible, 0, width_, p)) return false;
    }
    byItem_.assign(items_.size(), {});
    for (std::size_t k = 0; k < patterns_.size(); ++k) {
      for (std::size_t i = 0; i < items_.size(); ++i) if (patterns_[k].counts[i] > 0) byItem_[i].push_back(k);
    }
    return true;
  }

  // Branch and bound over what is left to cut. Returns true if the search finished.
  bool search(const std::vector<int>& demand, std::vector<Pattern>& best, Len& bestLen) {
    bestLen_ = bestLen;
    best_.clear();
    path_.clear();
    nodes_ = 0;
    memo_.clear();
    std::vector<int> rem = demand;
    dfs(rem, 0);
    if (!best_.empty()) {
      best.clear();
      for (auto k : best_) best.push_back(patterns_[k]);
      bestLen = bestLen_;
    }
    return nodes_ <= limits_.nodes;
  }

 private:
  bool fill(const std::vector<std::size_t>& eligible, std::size_t at, Len left, Pattern& p) {
    if (at == eligible.size()) {
      // Keep only patterns that can't take another piece, and whose tallest piece sets the height
      // (otherwise a shorter strip would do the same job).
      Len tallest = 0;
      bool any = false;
      for (auto i : eligible) {
        if (p.counts[i] == 0) continue;
        any = true;
        tallest = std::max(tallest, bestAt(items_[i], p.height).height);
      }
      if (!any || tallest != p.height) return true;
      for (auto i : eligible) {
        if (p.counts[i] < items_[i].demand && bestAt(items_[i], p.height).length <= left) return true;
      }
      if (patterns_.size() >= limits_.patterns) return false;
      patterns_.push_back(p);
      return true;
    }
    const auto i = eligible[at];
    const Len len = bestAt(items_[i], p.height).length;
    if (len <= 0) return fill(eligible, at + 1, left, p);  // only eligible items get here
    const int most = static_cast<int>(std::min<Len>(items_[i].demand, left / len));
    for (int n = most; n >= 0; --n) {
      p.counts[i] = n;
      if (!fill(eligible, at + 1, left - n * len, p)) return false;
    }
    p.counts[i] = 0;
    return true;
  }

  void dfs(std::vector<int>& rem, Len g) {
    if (++nodes_ > limits_.nodes) return;
    std::size_t pick = items_.size();
    for (std::size_t i = 0; i < items_.size(); ++i) {
      if (rem[i] == 0) continue;
      if (pick == items_.size() || items_[i].minHeight > items_[pick].minHeight ||
          (items_[i].minHeight == items_[pick].minHeight && items_[i].area * rem[i] > items_[pick].area * rem[pick])) {
        pick = i;
      }
    }
    if (pick == items_.size()) {
      if (g < bestLen_) { bestLen_ = g; best_ = path_; }
      return;
    }
    if (g + lowerBound(rem) >= bestLen_) return;
    std::string key(reinterpret_cast<const char*>(rem.data()), rem.size() * sizeof(int));
    if (auto it = memo_.find(key); it != memo_.end() && it->second <= g) return;
    memo_[key] = g;

    // Try the strips that cover the most per inch of fabric first.
    std::vector<std::pair<double, std::size_t>> order;
    for (auto k : byItem_[pick]) {
      long long covered = 0;
      for (std::size_t i = 0; i < items_.size(); ++i) covered += items_[i].area * std::min(rem[i], patterns_[k].counts[i]);
      order.emplace_back(-static_cast<double>(covered) / static_cast<double>(patterns_[k].height), k);
    }
    std::sort(order.begin(), order.end());
    for (const auto& [score, k] : order) {
      (void)score;
      std::vector<int> taken(items_.size());
      for (std::size_t i = 0; i < items_.size(); ++i) {
        taken[i] = std::min(rem[i], patterns_[k].counts[i]);
        rem[i] -= taken[i];
      }
      path_.push_back(k);
      dfs(rem, g + patterns_[k].height);
      path_.pop_back();
      for (std::size_t i = 0; i < items_.size(); ++i) rem[i] += taken[i];
      if (nodes_ > limits_.nodes) return;
    }
  }

  std::vector<Item> items_;
  Len width_;
  SearchLimits limits_;
  std::vector<Len> heights_;
  std::vector<Pattern> patterns_;
  std::vector<double> prices_;
  std::vector<std::vector<std::size_t>> byItem_;
  std::vector<std::size_t> path_, best_;
  Len bestLen_ = 0;
  long long nodes_ = 0;
  std::unordered_map<std::string, Len> memo_;
};

Len total(const std::vector<Pattern>& plan) {
  return std::accumulate(plan.begin(), plan.end(), Len{0}, [](Len s, const Pattern& p) { return s + p.height; });
}

struct StripResult {
  std::vector<Pattern> plan;
  Len length = 0;
  Len lowerBound = 0;
  bool proven = false;
};

StripResult solveStrips(const std::vector<Item>& items, Len width, SearchLimits limits) {
  StripResult r;
  if (items.empty()) { r.proven = true; return r; }
  std::vector<int> demand;
  demand.reserve(items.size());
  for (const auto& it : items) demand.push_back(it.demand);
  Solver s(items, width, limits);
  r.lowerBound = s.lowerBound(demand);
  r.plan = s.greedy(demand);
  r.length = total(r.plan);
  if (r.length == r.lowerBound) { r.proven = true; return r; }
  if (s.enumerate()) {
    s.price(demand);
    r.lowerBound = s.lowerBound(demand);
    if (r.length > r.lowerBound) r.proven = s.search(demand, r.plan, r.length);
  }
  if (r.length == r.lowerBound) r.proven = true;
  return r;
}

std::vector<Item> crosswiseItems(const Fabric& f, Len width, std::vector<Strip>& fullStrips) {
  std::vector<Item> items;
  for (const auto& p : f.pieces) {
    if (p.cut == Cut::Lengthwise) continue;
    Item it;
    it.demand = p.count;
    if (p.cut == Cut::Joined) {
      // Diagonal seams: each join uses about one strip width of length.
      const Len h = p.across, len = p.along;
      const Len k = ceilDiv(len - h, width - h);
      for (int c = 0; c < p.count; ++c) {
        for (Len j = 0; j + 1 < k; ++j) {
          Strip s;
          s.height = h;
          s.used = width;
          s.joinedFull = true;
          s.joinedName = p.name;
          fullStrips.push_back(s);
        }
      }
      const Len rest = len + (k - 1) * h - (k - 1) * width;
      it.name = p.name + " (last length)";
      it.options.push_back({h, rest, false});
      it.area = static_cast<long long>(h) * rest;
    } else {
      it.name = p.name;
      if (p.across <= width) it.options.push_back({p.along, p.across, false});
      if (!f.directional && p.along <= width && p.along != p.across) it.options.push_back({p.across, p.along, true});
      it.area = static_cast<long long>(p.across) * p.along;
    }
    for (const auto& o : it.options) {
      if (it.minHeight == 0 || o.height < it.minHeight) it.minHeight = o.height;
    }
    items.push_back(it);
  }
  return items;
}

// What pattern books usually do: every kind of piece in strips of its own.
Len naive(const std::vector<Item>& items, Len width) {
  Len sum = 0;
  for (const auto& it : items) {
    Len best = -1;
    for (const auto& o : it.options) {
      const Len per = width / o.length;
      const Len n = ceilDiv(it.demand, per);
      if (best < 0 || n * o.height < best) best = n * o.height;
    }
    sum += best;
  }
  return sum;
}

std::vector<Strip> toStrips(const std::vector<Pattern>& plan, const std::vector<Item>& items) {
  std::vector<int> rem;
  rem.reserve(items.size());
  for (const auto& it : items) rem.push_back(it.demand);
  std::vector<Strip> strips;
  for (const auto& p : plan) {
    Strip s;
    s.height = p.height;
    for (std::size_t i = 0; i < items.size(); ++i) {
      const int n = std::min(rem[i], p.counts[i]);
      if (n == 0) continue;
      rem[i] -= n;
      const auto o = bestAt(items[i], p.height);
      s.parts.push_back({items[i].name, n, o.length, o.height, o.turned});
      s.used += n * o.length;
    }
    if (!s.parts.empty()) strips.push_back(s);
  }
  return strips;
}

}  // namespace

FabricPlan planFabric(const Fabric& fabric, Len straighten, SearchLimits limits) {
  FabricPlan plan;
  const Len w = fabric.usableWidth();
  plan.usable = w;

  // Lengthwise pieces first, longest first, side by side in panels along the selvage.
  std::vector<LengthwisePart> longs;
  for (const auto& p : fabric.pieces) {
    if (p.cut != Cut::Lengthwise) continue;
    for (int c = 0; c < p.count; ++c) longs.push_back({p.name, p.across, p.along});
  }
  std::stable_sort(longs.begin(), longs.end(), [](const auto& a, const auto& b) { return a.along > b.along; });
  for (const auto& lp : longs) {
    auto it = std::find_if(plan.sections.begin(), plan.sections.end(), [&](const Section& s) { return s.used + lp.across <= w; });
    if (it == plan.sections.end()) {
      plan.sections.push_back({lp.along, 0, {}, {}});
      it = plan.sections.end() - 1;
    }
    it->used += lp.across;
    it->parts.push_back(lp);
  }

  // A joined length (binding) can often come from the fabric left beside a panel, as long strips.
  Fabric f = fabric;
  for (auto& p : f.pieces) {
    if (p.cut != Cut::Joined) continue;
    for (auto& s : plan.sections) {
      if (s.length <= 2 * p.across) continue;
      const Len k = ceilDiv(p.along - p.across, s.length - p.across);
      while (p.count > 0 && s.used + k * p.across <= w) {
        s.used += k * p.across;
        s.joined.push_back({p.name, static_cast<int>(k), p.across});
        --p.count;
      }
    }
  }
  f.pieces.erase(std::remove_if(f.pieces.begin(), f.pieces.end(), [](const Piece& p) { return p.count == 0; }), f.pieces.end());

  std::vector<Strip> full;
  const auto items = crosswiseItems(f, w, full);
  const auto result = solveStrips(items, w, limits);
  plan.strips = toStrips(result.plan, items);
  plan.strips.insert(plan.strips.end(), full.begin(), full.end());
  std::stable_sort(plan.strips.begin(), plan.strips.end(), [](const Strip& a, const Strip& b) {
    if (a.height != b.height) return a.height > b.height;
    return a.joinedFull < b.joinedFull;
  });
  Len fullLen = 0;
  for (const auto& s : full) fullLen += s.height;
  plan.stripLength = result.length + fullLen;
  plan.lowerBound = result.lowerBound + fullLen;
  plan.proven = result.proven;
  plan.naiveLength = naive(items, w) + fullLen;
  Len sectionLen = 0;
  for (const auto& s : plan.sections) sectionLen += s.length;

  for (const auto& p : fabric.pieces) plan.pieceArea += static_cast<long long>(p.across) * p.along * p.count;
  plan.cutLength = plan.stripLength + sectionLen;
  const Len before = plan.cutLength + straighten;
  plan.buyLength = before + (before * fabric.shrinkTenths + 999) / 1000;

  // A fat quarter: 18 inches along the selvage by about 21 across, one selvage edge.
  const bool simple = std::all_of(fabric.pieces.begin(), fabric.pieces.end(), [](const Piece& p) { return p.cut == Cut::Crosswise; });
  const Len fqWidth = 21 * kInch - fabric.selvage, fqLength = 18 * kInch - straighten;
  if (simple && plan.pieceArea <= static_cast<long long>(fqWidth) * fqLength) {
    std::vector<Strip> none;
    const auto fqItems = crosswiseItems(fabric, fqWidth, none);
    // Every piece needs a way to lie in a strip that narrow.
    const bool fits = std::all_of(fqItems.begin(), fqItems.end(), [](const Item& it) { return !it.options.empty(); });
    if (fits) {
      SearchLimits small{limits.nodes / 4, limits.patterns / 4};
      plan.fatQuarter = solveStrips(fqItems, fqWidth, small).length <= fqLength;
    }
  }
  return plan;
}

}  // namespace weftwise
