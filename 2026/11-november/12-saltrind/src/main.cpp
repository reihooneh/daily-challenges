// saltrind PLAN: how long to brine each batch of cheese, and what it does to the brine.
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "model.hpp"
#include "parse.hpp"
#include "report.hpp"

namespace fs = std::filesystem;

int main(int argc, char** argv) {
    if (argc != 2 || std::string_view(argv[1]) == "-h" || std::string_view(argv[1]) == "--help") {
        std::cerr << "usage: saltrind PLAN.txt\n"
                     "  PLAN.txt has one brine line and one cheese line per batch, e.g.\n"
                     "    brine litres=40 salt=23 temp=12\n"
                     "    cheese name=gouda diameter=22 height=9 moisture=42 count=3 target=4.5\n";
        return 2;
    }
    try {
        const fs::path path(argv[1]);
        // Only plain files: no folders, devices or links that could point somewhere unexpected.
        const auto status = fs::symlink_status(path);
        if (!fs::exists(status)) {
            std::cerr << "saltrind: the plan file was not found\n";
            return 1;
        }
        if (!fs::is_regular_file(status)) {
            std::cerr << "saltrind: the plan must be a plain file\n";
            return 1;
        }
        if (fs::file_size(path) > saltrind::kMaxFileBytes) {
            std::cerr << "saltrind: the plan is larger than 64 KB\n";
            return 1;
        }
        std::ifstream in(path, std::ios::binary);
        std::ostringstream text;
        text << in.rdbuf();
        const saltrind::Plan plan = saltrind::parsePlan(text.str());
        const auto brine = saltrind::Brine::make(plan.litres, plan.percent, plan.temp);
        std::cout << saltrind::report(plan, saltrind::brineAll(plan.wheels, brine, plan.restore));
        return 0;
    } catch (const saltrind::PlanError& e) {
        std::cerr << "saltrind: " << e.what() << '\n';
    } catch (const std::exception&) {
        std::cerr << "saltrind: the plan could not be read\n";
    }
    return 1;
}
