#include "report.hpp"

#include <algorithm>
#include <sstream>

namespace weftwise {
namespace {

std::string upper(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
  return s;
}

std::string plural(int n, const std::string& one, const std::string& many) {
  return std::to_string(n) + " " + (n == 1 ? one : many);
}

bool sameStrip(const Strip& a, const Strip& b) {
  if (a.height != b.height || a.joinedFull != b.joinedFull || a.joinedName != b.joinedName) return false;
  if (a.parts.size() != b.parts.size()) return false;
  for (std::size_t i = 0; i < a.parts.size(); ++i) {
    const auto &x = a.parts[i], &y = b.parts[i];
    if (x.name != y.name || x.count != y.count || x.length != y.length || x.height != y.height) return false;
  }
  return true;
}

void fabric(std::ostringstream& out, const Fabric& f, const FabricPlan& p, Len straighten) {
  out << upper(f.name) << "\n";
  out << "  " << inches(f.width) << "\" wide, " << inches(p.usable) << "\" to cut from after selvages";
  if (f.shrinkTenths > 0) out << " and " << f.shrinkTenths / 10 << (f.shrinkTenths % 10 ? "." + std::to_string(f.shrinkTenths % 10) : "") << "% shrinkage";
  out << (f.directional ? "; directional print, so pieces keep their up" : "; pieces may turn") << ".\n";
  out << "  Buy " << yardsRoundedUp(p.buyLength) << " (or " << metresRoundedUp(p.buyLength) << "): the cuts use "
      << inches(p.cutLength) << "\", plus " << inches(straighten) << "\" to straighten the end";
  if (f.shrinkTenths > 0) out << " and extra for shrinkage";
  out << ".\n";

  if (!p.strips.empty()) {
    if (p.proven) {
      out << "  " << inches(p.stripLength) << "\" of strips: the least possible when cutting in strips.\n";
    } else {
      out << "  " << inches(p.stripLength) << "\" of strips: the search stopped early, so this is within "
          << inches(p.stripLength - p.lowerBound) << "\" of the least possible.\n";
    }
    if (p.naiveLength > p.stripLength) {
      out << "  Cutting each kind of piece in strips of its own would take " << inches(p.naiveLength)
          << "\": this plan saves " << inches(p.naiveLength - p.stripLength) << "\".\n";
    }
  }
  const long long cutArea = static_cast<long long>(p.cutLength) * p.usable;
  if (cutArea > 0) {
    const long long waste = 100 - (p.pieceArea * 100 + cutArea / 2) / cutArea;
    out << "  About " << waste << "% of the fabric cut ends up as offcuts.\n";
  }
  if (p.fatQuarter) out << "  It all fits in one fat quarter (18\" x 21\") too.\n";

  out << "\n";
  for (const auto& s : p.sections) {
    out << "  First, cut a panel " << inches(s.length) << "\" long along the selvage, then from it:\n";
    for (std::size_t i = 0; i < s.parts.size();) {
      std::size_t j = i + 1;
      while (j < s.parts.size() && s.parts[j].name == s.parts[i].name) ++j;
      out << "      " << j - i << " x " << s.parts[i].name << ", " << inches(s.parts[i].across) << "\" wide x "
          << inches(s.parts[i].along) << "\" long\n";
      i = j;
    }
    for (const auto& j : s.joined) {
      out << "      " << j.name << ": " << plural(j.strips, "strip", "strips") << " " << inches(j.width) << "\" wide x "
          << inches(s.length) << "\" long, joined end to end\n";
    }
    if (p.usable - s.used >= kInch) {
      out << "      (" << inches(p.usable - s.used) << "\" x " << inches(s.length) << "\" left beside it for scraps)\n";
    }
  }
  for (std::size_t i = 0; i < p.strips.size();) {
    std::size_t j = i + 1;
    while (j < p.strips.size() && sameStrip(p.strips[i], p.strips[j])) ++j;
    const int n = static_cast<int>(j - i);
    const Strip& s = p.strips[i];
    out << "  Cut " << plural(n, "strip", "strips") << " " << inches(s.height) << "\" x the width of the fabric";
    if (s.joinedFull) {
      out << ", for " << s.joinedName << " (join end to end)\n";
    } else {
      out << (n > 1 ? "; from each:\n" : "; from it:\n");
      for (const auto& part : s.parts) {
        out << "      " << part.count << " x " << part.name << ", " << inches(part.length) << "\" x " << inches(part.height) << "\"";
        if (part.turned) out << " (turned)";
        if (part.height < s.height) out << ", then trim off the extra height";
        out << "\n";
      }
      if (p.usable - s.used >= kInch) out << "      (" << inches(p.usable - s.used) << "\" left at the end)\n";
    }
    i = j;
  }
  out << "\n";
}

}  // namespace

std::string render(const Quilt& quilt, const std::vector<FabricPlan>& plans) {
  std::ostringstream out;
  out << "WEFTWISE  " << quilt.name << "\n\n";
  Len saved = 0;
  for (std::size_t i = 0; i < quilt.fabrics.size(); ++i) {
    fabric(out, quilt.fabrics[i], plans[i], quilt.straighten);
    if (plans[i].naiveLength > plans[i].stripLength) saved += plans[i].naiveLength - plans[i].stripLength;
  }
  out << "SHOPPING LIST\n";
  for (std::size_t i = 0; i < quilt.fabrics.size(); ++i) {
    out << "  " << quilt.fabrics[i].name << ": " << yardsRoundedUp(plans[i].buyLength) << " (or "
        << metresRoundedUp(plans[i].buyLength) << ")" << (plans[i].fatQuarter ? ", or one fat quarter" : "") << "\n";
  }
  if (saved > 0) out << "  Smarter strips save " << inches(saved) << "\" of fabric in all.\n";
  out << "\nMeasurements include seam allowances as written. Check your fabric's real width before cutting.\n";
  return out.str();
}

}  // namespace weftwise
