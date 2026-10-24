// The cutting list as read from the file.
#pragma once

#include <string>
#include <vector>

#include "measure.hpp"

namespace weftwise {

enum class Cut {
  Crosswise,   // from strips cut selvage to selvage (the usual rotary-cutting way)
  Lengthwise,  // a long piece cut parallel to the selvage, such as an unpieced border
  Joined,      // a long strip made by joining crosswise strips with diagonal seams (binding)
};

struct Piece {
  std::string name;
  Len across = 0;  // the first number: across the fabric
  Len along = 0;   // the second number: along the selvage (up and down the print)
  int count = 1;
  Cut cut = Cut::Crosswise;
  int line = 0;
};

struct Fabric {
  std::string name;
  Len width = 42 * kInch;      // selvage to selvage
  Len selvage = 4;             // trimmed from each edge (default ½")
  int shrinkTenths = 0;        // pre-wash shrinkage allowance, tenths of a percent
  bool directional = false;    // the print has an up: pieces may not turn
  std::vector<Piece> pieces;
  int line = 0;

  // Width left for cutting once both selvages are trimmed and the fabric has shrunk.
  Len usableWidth() const {
    Len w = width - 2 * selvage;
    return w - (w * shrinkTenths + 999) / 1000;
  }
};

struct Quilt {
  std::string name = "Untitled quilt";
  Len straighten = 4;  // extra length bought per fabric to square up the cut end (default ½")
  std::vector<Fabric> fabrics;
};

// Thrown for anything wrong with the file; the message never repeats the input.
struct InputError {
  std::string message;
};

}  // namespace weftwise
