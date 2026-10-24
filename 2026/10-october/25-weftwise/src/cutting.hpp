// Plans the cuts for one fabric.
//
// The model is rotary cutting as quilters do it: strips are cut across the fabric from
// selvage to selvage, then each strip is subcut into pieces along its length. A strip's
// height is set by its tallest piece; shorter pieces in it are trimmed down. The goal is the
// least total length of fabric.
#pragma once

#include <string>
#include <vector>

#include "plan.hpp"

namespace weftwise {

struct StripPart {
  std::string name;
  int count = 0;
  Len length = 0;     // along the strip, each
  Len height = 0;     // of the piece itself (shorter than the strip means a trim)
  bool turned = false;  // cut with its across measurement up and down
};

struct Strip {
  Len height = 0;
  std::vector<StripPart> parts;
  Len used = 0;           // along the strip
  bool joinedFull = false;  // a whole strip for a joined length
  std::string joinedName;
};

struct LengthwisePart {
  std::string name;
  Len across = 0;
  Len along = 0;
};

struct JoinedPart {  // long strips from a panel, joined end to end
  std::string name;
  int strips = 0;
  Len width = 0;
};

struct Section {  // a panel cut parallel to the selvage, pieces side by side
  Len length = 0;
  Len used = 0;   // across
  std::vector<LengthwisePart> parts;
  std::vector<JoinedPart> joined;
};

struct FabricPlan {
  Len usable = 0;           // width to cut from
  std::vector<Strip> strips;  // in cutting order: tallest first
  std::vector<Section> sections;
  Len stripLength = 0;      // total height of the strips
  Len cutLength = 0;        // strips + lengthwise sections
  Len buyLength = 0;        // plus straightening and shrinkage
  Len lowerBound = 0;       // no strip plan can be shorter than this
  bool proven = false;      // stripLength is the least possible for strip cutting
  Len naiveLength = 0;      // each kind of piece in strips of its own, as many patterns say
  long long pieceArea = 0;  // square eighths
  bool fatQuarter = false;  // the cuts also fit in one fat quarter (18 x 21 inches)
};

struct SearchLimits {
  long long nodes = 1000000;
  std::size_t patterns = 20000;
};

FabricPlan planFabric(const Fabric& fabric, Len straighten, SearchLimits limits = {});

}  // namespace weftwise
