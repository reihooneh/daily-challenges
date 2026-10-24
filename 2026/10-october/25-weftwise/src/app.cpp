#include "app.hpp"

#include <filesystem>
#include <fstream>
#include <optional>

#include "cutting.hpp"
#include "parse.hpp"
#include "report.hpp"

namespace weftwise {
namespace {

constexpr const char* kUsage =
    "usage: weftwise <cutting-list.txt>   (or - to read standard input)\n"
    "Plans the fabric cuts for a quilt and how much of each fabric to buy.\n";

// Reads at most kMaxInput + 1 bytes, so an endless stream is cut off and reported.
std::string readBounded(std::istream& in) {
  std::string data(kMaxInput + 1, '\0');
  in.read(data.data(), static_cast<std::streamsize>(data.size()));
  data.resize(static_cast<std::size_t>(in.gcount()));
  return data;
}

std::optional<std::string> readFile(const std::string& path) {
  std::error_code ec;
  if (!std::filesystem::is_regular_file(path, ec) || ec) return std::nullopt;
  std::ifstream f(path, std::ios::binary);
  if (!f) return std::nullopt;
  return readBounded(f);
}

}  // namespace

int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err) {
  if (args.size() != 1 || args[0] == "--help" || args[0] == "-h") {
    err << kUsage;
    return 2;
  }
  std::optional<std::string> text = args[0] == "-" ? std::optional<std::string>(readBounded(in)) : readFile(args[0]);
  if (!text) {
    err << "weftwise: the cutting list could not be read (it must be a readable file)\n";
    return 2;
  }
  try {
    const Quilt quilt = parse(*text);
    std::vector<FabricPlan> plans;
    plans.reserve(quilt.fabrics.size());
    for (const auto& f : quilt.fabrics) plans.push_back(planFabric(f, quilt.straighten));
    out << render(quilt, plans);
    return 0;
  } catch (const InputError& e) {
    err << "weftwise: " << e.message << "\n";
    return 2;
  }
}

}  // namespace weftwise
