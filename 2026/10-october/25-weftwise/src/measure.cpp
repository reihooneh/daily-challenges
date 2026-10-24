#include "measure.hpp"

#include <array>
#include <cctype>

namespace weftwise {
namespace {

// Up to 4 digits, nothing else: no signs, exponents or spaces.
std::optional<std::int64_t> digits(std::string_view s) {
  if (s.empty() || s.size() > 4) return std::nullopt;
  std::int64_t v = 0;
  for (char c : s) {
    if (c < '0' || c > '9') return std::nullopt;
    v = v * 10 + (c - '0');
  }
  return v;
}

// A fraction "n/d" with d one of 2, 4 or 8, as eighths.
std::optional<Len> fraction(std::string_view s) {
  auto slash = s.find('/');
  if (slash == std::string_view::npos) return std::nullopt;
  auto n = digits(s.substr(0, slash));
  auto d = digits(s.substr(slash + 1));
  if (!n || !d || (*d != 2 && *d != 4 && *d != 8) || *n == 0 || *n >= *d) return std::nullopt;
  return *n * (8 / *d);
}

constexpr std::array<const char*, 8> kFractions = {"", "⅛", "¼", "⅜", "½", "⅝", "¾", "⅞"};

}  // namespace

std::optional<Len> parseInches(std::string_view text, Len max) {
  std::optional<Len> value;
  if (auto dash = text.find('-'); dash != std::string_view::npos) {
    auto whole = digits(text.substr(0, dash));
    auto part = fraction(text.substr(dash + 1));
    if (whole && part) value = *whole * kInch + *part;
  } else if (text.find('/') != std::string_view::npos) {
    value = fraction(text);
  } else if (auto dot = text.find('.'); dot != std::string_view::npos) {
    auto whole = digits(text.substr(0, dot));
    auto dec = text.substr(dot + 1);
    if (whole && !dec.empty() && dec.size() <= 3) {
      auto d = digits(dec);
      if (d) {
        // Scale the decimal part to thousandths, then it must be a multiple of 125 (an eighth).
        std::int64_t thousandths = *d;
        for (std::size_t i = dec.size(); i < 3; ++i) thousandths *= 10;
        if (thousandths % 125 == 0) value = *whole * kInch + thousandths / 125;
      }
    }
  } else {
    auto whole = digits(text);
    if (whole) value = *whole * kInch;
  }
  if (!value || *value > max) return std::nullopt;
  return value;
}

std::optional<int> parsePercentTenths(std::string_view text) {
  if (text.size() < 2 || text.back() != '%') return std::nullopt;
  text.remove_suffix(1);
  std::int64_t tenths = 0;
  if (auto dot = text.find('.'); dot != std::string_view::npos) {
    auto whole = digits(text.substr(0, dot));
    auto dec = digits(text.substr(dot + 1));
    if (!whole || !dec || text.size() - dot - 1 != 1) return std::nullopt;
    tenths = *whole * 10 + *dec;
  } else {
    auto whole = digits(text);
    if (!whole) return std::nullopt;
    tenths = *whole * 10;
  }
  if (tenths > 100) return std::nullopt;
  return static_cast<int>(tenths);
}

std::string inches(Len eighths) {
  std::string out = std::to_string(eighths / kInch);
  Len rest = eighths % kInch;
  if (rest == 0) return out;
  if (eighths < kInch) out.clear();
  return out + kFractions[static_cast<std::size_t>(rest)];
}

std::string yardsRoundedUp(Len eighths) {
  const Len step = kYard / 8;  // 4½ inches
  Len steps = (eighths + step - 1) / step;
  Len whole = steps / 8;
  Len rest = steps % 8;
  std::string out;
  if (whole > 0) out = std::to_string(whole);
  if (rest > 0) out += kFractions[static_cast<std::size_t>(rest)];
  if (out.empty()) out = "0";
  return out + " yd";
}

std::string metresRoundedUp(Len eighths) {
  // 1 inch = 2.54 cm exactly, so one eighth = 0.3175 cm = 3175 / 10000 cm.
  // Tenths of a metre = 10 cm = 100000 / 3175 eighths; round up with integers only.
  Len tenths = (eighths * 3175 + 99999) / 100000;
  return std::to_string(tenths / 10) + "." + std::to_string(tenths % 10) + " m";
}

}  // namespace weftwise
