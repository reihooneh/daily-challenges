// Tests for Weftwise. Build and run with:  make test
// (compiled with AddressSanitizer and UndefinedBehaviorSanitizer)
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "app.hpp"
#include "cutting.hpp"
#include "measure.hpp"
#include "parse.hpp"
#include "report.hpp"

using namespace weftwise;

namespace {

int checks = 0, failures = 0;

void check(bool ok, const std::string& what) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cout << "FAIL: " << what << "\n";
  }
}

void rejects(const std::string& text, const std::string& fragment) {
  try {
    parse(text);
    check(false, "should reject (" + fragment + ")");
  } catch (const InputError& e) {
    check(e.message.find(fragment) != std::string::npos, "rejects with '" + fragment + "' (got: " + e.message + ")");
  }
}

FabricPlan planOf(const std::string& text, SearchLimits limits = {}) {
  const Quilt q = parse(text);
  return planFabric(q.fabrics.at(0), q.straighten, limits);
}

// Every piece is cut once, nothing overflows its strip, and the lengths add up.
bool validPlan(const Fabric& f, const FabricPlan& p) {
  std::map<std::string, int> cut;
  Len stripLen = 0;
  for (const auto& s : p.strips) {
    stripLen += s.height;
    if (s.joinedFull) continue;
    Len used = 0;
    for (const auto& part : s.parts) {
      if (part.height > s.height || part.count <= 0) return false;
      used += part.length * part.count;
      cut[part.name] += part.count;
    }
    if (used != s.used || used > p.usable) return false;
  }
  for (const auto& sec : p.sections) {
    Len across = 0;
    for (const auto& part : sec.parts) {
      across += part.across;
      if (part.along > sec.length) return false;
      cut[part.name] += 1;
    }
    for (const auto& j : sec.joined) across += j.strips * j.width;
    if (across != sec.used || across > p.usable) return false;
  }
  for (const auto& piece : f.pieces) {
    if (piece.cut == Cut::Crosswise && cut[piece.name] != piece.count) return false;
    if (piece.cut == Cut::Lengthwise && cut[piece.name] != piece.count) return false;
  }
  return stripLen == p.stripLength && p.lowerBound <= p.stripLength;
}

// An independent, exhaustive answer for tiny cutting lists: try every strip height and every
// way to fill it, remembering the best for each set of pieces still to cut.
Len bruteForce(const Fabric& f) {
  const Len w = f.usableWidth();
  struct T { Len a, b; bool dir; };
  std::vector<T> types;
  std::vector<int> demand;
  for (const auto& p : f.pieces) {
    types.push_back({p.across, p.along, f.directional});
    demand.push_back(p.count);
  }
  std::vector<Len> heights;
  for (const auto& t : types) { heights.push_back(t.b); if (!t.dir) heights.push_back(t.a); }
  auto lenAt = [&](const T& t, Len h) -> Len {
    Len best = 0;
    if (t.b <= h && t.a <= w) best = t.a;
    if (!t.dir && t.a <= h && t.b <= w && (best == 0 || t.b < best)) best = t.b;
    return best;
  };
  std::map<std::vector<int>, Len> memo;
  std::function<Len(const std::vector<int>&)> solve = [&](const std::vector<int>& rem) -> Len {
    bool done = true;
    for (int r : rem) if (r > 0) done = false;
    if (done) return 0;
    if (auto it = memo.find(rem); it != memo.end()) return it->second;
    Len best = INT64_MAX;
    for (Len h : heights) {
      std::vector<int> take(rem.size(), 0);
      std::function<void(std::size_t, Len)> go = [&](std::size_t i, Len left) {
        if (i == rem.size()) {
          bool any = false;
          std::vector<int> next = rem;
          for (std::size_t k = 0; k < rem.size(); ++k) { any = any || take[k] > 0; next[k] -= take[k]; }
          if (any) best = std::min(best, h + solve(next));
          return;
        }
        const Len len = lenAt(types[i], h);
        for (int n = 0; n <= rem[i] && (n == 0 || (len > 0 && n * len <= left)); ++n) {
          take[i] = n;
          go(i + 1, left - (len > 0 ? n * len : 0));
        }
        take[i] = 0;
      };
      go(0, w);
    }
    memo[rem] = best;
    return best;
  };
  return solve(demand);
}

void measures() {
  check(parseInches("6.5", 100 * kInch) == 52, "6.5 inches");
  check(parseInches("6-1/2", 100 * kInch) == 52, "6-1/2 inches");
  check(parseInches("1/4", 100 * kInch) == 2, "a quarter inch");
  check(parseInches("2.125", 100 * kInch) == 17, "2.125 is 2⅛");
  check(parseInches("42", 100 * kInch) == 336, "whole inches");
  check(!parseInches("2.3", 100 * kInch), "2.3 is not on an eighth");
  check(!parseInches("5/16", 100 * kInch), "sixteenths are refused");
  check(!parseInches("3/3", 100 * kInch), "improper fractions are refused");
  check(!parseInches("-1", 100 * kInch) && !parseInches("1e1", 100 * kInch) && !parseInches("", 100 * kInch), "no signs, exponents or blanks");
  check(!parseInches("101", 100 * kInch), "the maximum is enforced");
  check(!parseInches("99999999999", 100 * kInch), "huge numbers are refused before they overflow");
  check(parsePercentTenths("3%") == 30 && parsePercentTenths("2.5%") == 25, "percentages");
  check(!parsePercentTenths("11%") && !parsePercentTenths("3") && !parsePercentTenths("2.55%"), "bad percentages");
  check(inches(52) == "6½" && inches(2) == "¼" && inches(336) == "42" && inches(0) == "0", "printing inches");
  check(yardsRoundedUp(36) == "⅛ yd" && yardsRoundedUp(kYard) == "1 yd" && yardsRoundedUp(kYard + 1) == "1⅛ yd", "yards round up to eighths");
  check(metresRoundedUp(315) == "1.1 m" && metresRoundedUp(314) == "1.0 m", "metres round up to 10 cm");
}

void parsing() {
  const Quilt q = parse("quilt Lap\nstraighten 1\nfabric Big blue\nwidth 44\nselvage 1/4\nshrink 2%\ndirectional\n"
                        "piece Corner square 2.5 x 2.5 count 4\npiece Border 4.5 x 64.5 lengthwise\n");
  check(q.name == "Lap" && q.straighten == 8, "quilt settings");
  const Fabric& f = q.fabrics[0];
  check(f.name == "Big blue" && f.width == 352 && f.selvage == 2 && f.shrinkTenths == 20 && f.directional, "fabric settings");
  check(f.usableWidth() == 348 - (348 * 20 + 999) / 1000, "usable width after selvage and shrinkage");
  check(f.pieces[0].name == "Corner square" && f.pieces[0].count == 4, "multi-word piece names and counts");
  check(f.pieces[1].cut == Cut::Lengthwise && f.pieces[1].across == 36 && f.pieces[1].along == 516, "a directional lengthwise piece keeps its sides");
  const Quilt g = parse("fabric A\npiece Border 64.5 x 4.5 lengthwise\npiece Bind 2.5 x 30 join\npiece Long 2.5 x 300 join\n");
  check(g.fabrics[0].pieces[0].across == 36 && g.fabrics[0].pieces[0].along == 516, "a lengthwise piece is turned to run along the selvage");
  check(g.fabrics[0].pieces[1].cut == Cut::Crosswise && g.fabrics[0].pieces[1].across == 240, "a short joined strip is just a strip");
  check(g.fabrics[0].pieces[2].cut == Cut::Joined && g.fabrics[0].pieces[2].across == 20, "a long joined strip stays joined");
  check(parse("\xEF\xBB\xBF" "fabric A\npiece P 1 x 1\n").fabrics.size() == 1, "a byte-order mark is skipped");

  const std::string ok = "fabric A\npiece P 2 x 3\n";
  rejects("", "no fabrics");
  rejects("fabric A\n", "no pieces");
  rejects("piece P 2 x 3\n", "belongs under a 'fabric' line");
  rejects(ok + "fabric A\npiece P 2 x 3\n", "already a fabric with that name");
  rejects(ok + "piece P 1 x 1\n", "already has a piece with that name");
  rejects("fabric A\npiece P 2.3 x 3\n", "exact to 1/8 inch");
  rejects("fabric A\npiece P 2 by 3\n", "write pieces as");
  rejects("fabric A\npiece P 2 x 3 count 0\n", "count must be");
  rejects("fabric A\npiece P 2 x 3 count 1000\n", "count must be");
  rejects("fabric A\npiece P 2 x 3 count x\n", "count must be");
  rejects("fabric A\npiece P 2 x 3 lengthwise join\n", "can only have");
  rejects("fabric A\npiece P 50 x 2\ndirectional\n", "longer than the usable width");
  rejects("fabric A\npiece P 45 x 50\n", "mark it 'lengthwise'");
  rejects("fabric A\npiece P 20 x 300 join\n", "joined strips must be");
  rejects("fabric A\nwidth 9\npiece P 1 x 1\n", "between 10 and 120");
  rejects("fabric A\nwidth 11\nselvage 2\npiece P 1 x 1\n", "narrower than 8 inches");
  rejects("fabric A\nshrink 12%\npiece P 1 x 1\n", "shrink is a percentage");
  rejects(ok + "quilt Late\n", "comes once, before the first fabric");
  rejects(ok + "colour red\n", "lines start with");
  rejects("fabric <script>\npiece P 1 x 1\n", "names use letters");
  rejects("fabric A\npiece P\x1b[2J 1 x 1\n", "control or hidden");
  rejects("fabric A\xe2\x80\xae\npiece P 1 x 1\n", "control or hidden");
  rejects("fabric A\xe2\x80\x8b\npiece P 1 x 1\n", "control or hidden");
  rejects("fabric A\xff\npiece P 1 x 1\n", "not valid UTF-8");
  rejects("fabric A\xc0\xaf\npiece P 1 x 1\n", "not valid UTF-8");
  rejects("fabric " + std::string(70, 'x') + "\npiece P 1 x 1\n", "at most 60 characters");
  rejects("# " + std::string(300, 'x') + "\n" + ok, "longer than 200 characters");
  rejects(std::string(70000, '\n'), "larger than 64 KB");
  std::string many = "fabric A\n";
  for (int i = 0; i < 13; ++i) many += "piece P" + std::to_string(i) + " 1 x 1\n";
  rejects(many, "at most 12 kinds");
  std::string fabrics;
  for (int i = 0; i < 13; ++i) fabrics += "fabric F" + std::to_string(i) + "\npiece P 1 x 1\n";
  rejects(fabrics, "at most 12 fabrics");
  std::string lots = "fabric A\n";
  for (int i = 0; i < 6; ++i) lots += "piece P" + std::to_string(i) + " 1 x 1 count 400\n";
  rejects(lots, "at most 2000 pieces");
}

void cutting() {
  // Sixteen 5" squares from 40" usable: 8 to a strip, two strips, provably best.
  const std::string sq = "fabric A\nwidth 41\nselvage 0.5\npiece Square 5 x 5 count 16\n";
  const auto p = planOf(sq);
  check(p.usable == 320 && p.stripLength == 80 && p.proven && p.strips.size() == 2, "squares fill whole strips");
  check(p.buyLength == 84, "buying adds the straightening allowance");

  // Pieces that can turn share a strip; the same pieces with a directional print can't.
  const std::string turn = "fabric A\nwidth 41\nselvage 0.5\npiece Tall 2 x 10 count 20\n";
  const auto t = planOf(turn);
  check(t.stripLength == 2 * kInch * 5 && t.proven, "non-directional pieces lie down in 2\" strips");
  const auto d = planOf("fabric A\nwidth 41\nselvage 0.5\ndirectional\npiece Tall 2 x 10 count 20\n");
  check(d.stripLength == 10 * kInch, "directional pieces stand up in a 10\" strip");
  check(d.strips[0].parts[0].turned == false && t.strips[0].parts[0].turned, "and the plan says which were turned");

  // Mixing sizes in one strip beats one strip per kind of piece.
  const std::string mix = "fabric A\nwidth 41\nselvage 0.5\npiece Big 6 x 6 count 5\npiece Small 2 x 6 count 5\n";
  const auto m = planOf(mix);
  check(m.stripLength == 6 * kInch && m.naiveLength == 8 * kInch && m.proven, "mixing pieces saves a strip");

  // Joined binding: 274" of 2½" strips from 41" usable needs 8 strips with diagonal joins.
  const std::string bind = "fabric A\nwidth 42\nselvage 0.5\npiece Binding 2.5 x 274 join\n";
  const Quilt bq = parse(bind);
  const auto b = planFabric(bq.fabrics[0], bq.straighten);
  int full = 0;
  Len rest = 0;
  for (const auto& s : b.strips) {
    if (s.joinedFull) ++full;
    else rest = s.parts.at(0).length;
  }
  check(full == 7 && rest == 36 && b.stripLength == 8 * 20, "binding: 7 full strips and 4½\" of an eighth");
  check(7 * 328 + rest - 7 * 20 == 274 * 8, "the joined pieces add up to the length asked for");
  check(validPlan(bq.fabrics[0], b), "binding plan is consistent");

  // Lengthwise borders, with the binding cut from the fabric left beside them.
  const std::string border = "fabric A\nwidth 42\nselvage 0.5\npiece Side 4.5 x 64.5 count 2 lengthwise\n"
                             "piece Top 4.5 x 60.5 count 2 lengthwise\npiece Binding 2.5 x 274 join\n";
  const Quilt lq = parse(border);
  const auto l = planFabric(lq.fabrics[0], lq.straighten);
  check(l.sections.size() == 1 && l.sections[0].length == 516 && l.sections[0].parts.size() == 4, "borders share one panel");
  check(l.sections[0].joined.size() == 1 && l.sections[0].joined[0].strips == 5 && l.strips.empty(), "binding comes from beside the borders");
  check(l.cutLength == 516 && validPlan(lq.fabrics[0], l), "nothing else needs cutting");
  const auto wide = planOf("fabric A\nwidth 42\nselvage 0.5\npiece Panel 30 x 50 count 2 lengthwise\n");
  check(wide.sections.size() == 2 && wide.cutLength == 100 * kInch, "panels too wide to share are cut one after the other");

  // Shrinkage: 3% more length bought.
  const auto s = planOf("fabric A\nwidth 41\nselvage 0.5\nshrink 3%\npiece Square 5 x 5 count 7\n");
  check(s.usable == 320 - 10 && s.buyLength == 44 + 2, "shrinkage narrows the width and adds length");

  // Fat quarters.
  check(planOf("fabric A\npiece Square 5 x 5 count 9\n").fatQuarter, "nine 5\" squares fit a fat quarter");
  check(!planOf("fabric A\npiece Square 5 x 5 count 16\n").fatQuarter, "sixteen don't");
  check(!planOf("fabric A\npiece Strip 2 x 30\n").fatQuarter, "a 30\" strip doesn't");

  // A starved search still returns a complete, honest plan.
  const std::string busy = "fabric A\npiece A 4.5 x 4.5 count 30\npiece B 2.5 x 2.5 count 120\n"
                           "piece C 2.5 x 9.5 count 49\npiece D 2.5 x 6.5 count 20\n";
  const Quilt bz = parse(busy);
  const auto starved = planFabric(bz.fabrics[0], bz.straighten, SearchLimits{10, 5});
  check(validPlan(bz.fabrics[0], starved) && !starved.proven, "a tiny search budget still gives a valid plan");
  const auto full2 = planFabric(bz.fabrics[0], bz.straighten);
  check(validPlan(bz.fabrics[0], full2) && full2.stripLength <= starved.stripLength, "a full search is never worse");
  check(full2.stripLength <= full2.naiveLength, "and never worse than strips of one kind each");

  // Against exhaustive search on many small random cutting lists.
  std::uint32_t seed = 12345;
  auto rnd = [&](std::uint32_t n) {
    seed = seed * 1664525u + 1013904223u;
    return (seed >> 8) % n;
  };
  int agree = 0, provenCount = 0;
  const int trials = 150;
  for (int trial = 0; trial < trials; ++trial) {
    std::ostringstream text;
    text << "fabric R\nwidth " << 10 + rnd(7) << "\nselvage 0.5\n";
    if (rnd(3) == 0) text << "directional\n";
    const std::uint32_t kinds = 1 + rnd(3);
    for (std::uint32_t k = 0; k < kinds; ++k) {
      text << "piece P" << k << " " << 1 + rnd(5) << "." << (rnd(2) ? 5 : 0) << " x " << 1 + rnd(6) << "."
           << (rnd(2) ? 5 : 0) << " count " << 1 + rnd(4) << "\n";
    }
    const Quilt rq = parse(text.str());
    const Fabric& rf = rq.fabrics[0];
    const auto plan = planFabric(rf, 0);
    const Len best = bruteForce(rf);
    const bool valid = validPlan(rf, plan);
    const bool ok = valid && plan.stripLength >= best && plan.lowerBound <= best && (!plan.proven || plan.stripLength == best);
    if (!ok) std::cout << "  random case " << trial << ": plan " << plan.stripLength << ", best " << best << "\n" << text.str();
    agree += ok;
    provenCount += plan.proven;
  }
  check(agree == trials, "random cutting lists: valid plans, valid bounds, and 'proven' always means optimal");
  check(provenCount >= trials * 9 / 10, "and most small lists are proven optimal (" + std::to_string(provenCount) + ")");
}

void reporting() {
  const Quilt q = parse("quilt Test\nfabric A\nwidth 41\nselvage 0.5\npiece Square 5 x 5 count 16\n");
  const std::string r = render(q, {planFabric(q.fabrics[0], q.straighten)});
  check(r.find("WEFTWISE  Test") == 0, "report title");
  check(r.find("Cut 2 strips 5\" x the width of the fabric; from each:\n      8 x Square, 5\" x 5\"\n") != std::string::npos, "identical strips are merged");
  check(r.find("the least possible") != std::string::npos && r.find("Buy ⅜ yd (or 0.3 m)") != std::string::npos, "proof and purchase");
}

void commandLine() {
  std::ostringstream out, err;
  std::istringstream none;
  check(run({"examples/garden-path.txt"}, none, out, err) == 0 && out.str().find("SHOPPING LIST") != std::string::npos, "the example runs");
  std::ifstream f("examples/garden-path.txt");
  std::stringstream text;
  text << f.rdbuf();
  std::ostringstream out2, err2;
  check(run({"-"}, text, out2, err2) == 0 && out2.str() == out.str(), "standard input gives the same plan");
  std::ostringstream o3, e3;
  check(run({}, none, o3, e3) == 2 && run({"--help"}, none, o3, e3) == 2 && run({"a", "b"}, none, o3, e3) == 2, "usage errors exit 2");
  std::ostringstream o4, e4;
  check(run({"examples"}, none, o4, e4) == 2 && e4.str().find("could not be read") != std::string::npos, "a folder is refused");
  std::ostringstream o5, e5;
  check(run({"secret-name-zz.txt"}, none, o5, e5) == 2 && e5.str().find("secret-name") == std::string::npos, "errors don't echo the path");
  std::istringstream endless(std::string(200000, '#'));
  std::ostringstream o6, e6;
  check(run({"-"}, endless, o6, e6) == 2 && e6.str().find("larger than 64 KB") != std::string::npos, "big input is cut off");
  std::istringstream bad("fabric A\npiece <img> 1 x 1\n");
  std::ostringstream o7, e7;
  check(run({"-"}, bad, o7, e7) == 2 && e7.str().find("<img>") == std::string::npos, "input errors don't echo the input");
  for (const char* ex : {"examples/pincushion.txt", "examples/garden-path.txt"}) {
    std::ostringstream o, e;
    check(run({ex}, none, o, e) == 0 && e.str().empty(), std::string(ex) + " runs cleanly");
  }
}

}  // namespace

int main() {
  try {
  measures();
  parsing();
  cutting();
  reporting();
  commandLine();
  } catch (const InputError& e) { std::cout << "unexpected: " << e.message << "\n"; return 1; }
  std::cout << checks << " checks, " << failures << " failed\n";
  return failures == 0 ? 0 : 1;
}
