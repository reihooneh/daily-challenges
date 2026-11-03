package gapsmith;

import java.util.ArrayList;
import java.util.List;

/** The printed plan: the short circuit, where to cut, and how to wire every section. */
public final class Report {
    private Report() {}

    static String joinLabel(Layout l, int j) {
        Layout.Join jn = l.joins.get(j);
        return jn.a().label(l) + " / " + jn.b().label(l);
    }

    static String names(Layout l, List<Integer> sections) {
        List<String> out = new ArrayList<>();
        for (int s : sections) out.add(l.sections.get(s).id());
        return String.join(", ", out);
    }

    public static String render(Layout l, Planner.Plan p) {
        StringBuilder b = new StringBuilder();
        long turnouts = l.sections.stream().filter(Layout.Section::turnout).count();
        b.append("GAPSMITH  ").append(l.title).append('\n');
        b.append(l.sections.size()).append(" sections (").append(turnouts).append(turnouts == 1 ? " turnout), " : " turnouts), ")
                .append(l.joins.size()).append(" joins; longest train ").append(Layout.metres(l.train)).append(".\n\n");

        if (p.alreadyFine()) {
            b.append("No reversing loops: every rail meets a rail of the same polarity, so one booster or\n");
            b.append("DC controller can feed the whole layout without any cuts.\n\n");
        } else {
            b.append("SHORT CIRCUIT: a train going round this loop comes back facing the other way, so its\n");
            b.append("rails meet the opposite rails somewhere on the way:\n");
            for (int j : p.loop()) {
                Layout.Join jn = l.joins.get(j);
                b.append(String.format("  %-26s %s  (line %d)%n", joinLabel(l, j), jn.same() ? "rails continue" : "rails cross   ", jn.line()));
            }
            b.append('\n');
            if (p.reversers().isEmpty()) {
                b.append("NO FIX FOUND: ").append(p.problem()).append(".\n");
                b.append("Lengthen the loop, run shorter trains, or wire it by hand with a polarity-switching turnout.\n");
                return b.toString();
            }
            int k = 1;
            for (Planner.Reverser r : p.reversers()) {
                b.append(p.reversers().size() == 1 ? "FIX: one reversing section, fed by an auto-reverser\n" : "FIX " + k + " of " + p.reversers().size() + ": a reversing section with its own auto-reverser\n");
                b.append("  Sections: ").append(names(l, r.sections())).append('\n');
                b.append("  Length:   ").append(Layout.metres(r.length())).append(", longer than the ").append(Layout.metres(l.train))
                        .append(" train, so a train is never across both ends at once\n");
                b.append("  Cut both rails (insulated joiners) at:\n");
                for (int j : r.cuts()) b.append(String.format("    %-26s (line %d)%n", joinLabel(l, j), l.joins.get(j).line()));
                k++;
            }
            int cuts = p.reversers().stream().mapToInt(r -> r.cuts().size()).sum();
            b.append(String.format("%d cut%s in all: %d insulated rail joiners.%n", cuts, cuts == 1 ? "" : "s", cuts * 2));
            if (!p.searchedAll()) b.append("(The layout is large, so the search stopped at its limit; a better plan may exist.)\n");
            b.append('\n');
        }

        b.append("WIRING: connect the red feeder to the rail named, black to the other.\n");
        for (int s = 0; s < l.sections.size(); s++) {
            Layout.Section sec = l.sections.get(s);
            int pol = p.polarity()[s];
            String rail;
            if (pol == 0) rail = "from the auto-reverser (either way round)";
            else rail = (pol > 0 ? "left" : "right") + " rail, facing " + (sec.turnout() ? "from the points (p) towards the frog" : "from end a to end b");
            b.append(String.format("  %-16s %s%n", sec.id(), rail));
        }
        return b.toString();
    }
}
