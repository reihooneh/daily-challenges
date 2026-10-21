package ferryglide;

import java.util.Locale;

/** The printed plan. */
public final class Report {
    private Report() {}

    static String clock(double minutes) {
        long m = Math.round(minutes);
        long day = Math.floorDiv(m, 24 * 60);
        long h = Math.floorMod(m, 24 * 60) / 60, mm = Math.floorMod(m, 60);
        return String.format(Locale.ROOT, "%02d:%02d%s", h, mm, day > 0 ? " (+" + day + "d)" : "");
    }

    static String duration(double minutes) {
        long m = Math.round(minutes);
        return m >= 60 ? String.format(Locale.ROOT, "%dh %02dm", m / 60, m % 60) : m + " min";
    }

    public static String render(Plan plan, Planner.Result r) {
        StringBuilder out = new StringBuilder();
        double total = plan.legs().stream().mapToDouble(Plan.Leg::distance).sum();
        out.append(String.format(Locale.ROOT, "FERRYGLIDE  %s%n", plan.trip()));
        out.append(String.format(Locale.ROOT, "%d %s, %.1f nm at %.1f kn (%s in still water). Leaving between %s and %s.%n%n",
                plan.legs().size(), plan.legs().size() == 1 ? "leg" : "legs", total, plan.paddle(), duration(r.stillWaterMinutes()),
                clock(plan.windowStart()), clock(plan.windowEnd())));

        out.append(timeline(plan, r)).append('\n');

        if (r.windows().isEmpty()) {
            out.append("No departure in the window keeps within your limits");
            out.append(String.format(Locale.ROOT, " (%.1f kn against you, %.1f kn across).%n", plan.maxOpposing(), plan.maxCross()));
            if (r.fastestIgnoringLimits() != null) {
                Navigator.Trip f = r.fastestIgnoringLimits();
                out.append(String.format(Locale.ROOT, "The quickest trip that finishes leaves at %s and takes %s, but %s.%n",
                        clock(f.departure()), duration(f.minutes()), f.failure() == null ? "it keeps within limits" : f.failure()));
            } else {
                out.append("No departure in the window gets you there at all. Try another day or a wider window.\n");
            }
            return out.toString();
        }
        out.append("Good times to leave:\n");
        for (Planner.Window w : r.windows()) {
            out.append(String.format(Locale.ROOT, "  %s to %s   trip takes %s to %s%n", clock(w.from()), clock(w.to()),
                    duration(w.fastest()), duration(w.slowest())));
        }
        Navigator.Trip b = r.best();
        out.append(String.format(Locale.ROOT, "%nBest: leave at %s, arrive %s (%s, %s than still water).%n%n", clock(b.departure()),
                clock(b.arrival()), duration(b.minutes()),
                b.minutes() <= r.stillWaterMinutes() ? duration(r.stillWaterMinutes() - b.minutes()) + " faster"
                        : duration(b.minutes() - r.stillWaterMinutes()) + " slower"));
        out.append("  Leg                              Start   End     Steer   Against  Across\n");
        for (Navigator.LegRun leg : b.legs()) {
            String name = leg.leg().name();
            if (name.length() > 31) name = name.substring(0, 30) + "…";
            out.append(String.format(Locale.ROOT, "  %-31s  %s   %s   %03.0f°   %4.1f kn  %4.1f kn%n", name, clock(leg.start()),
                    clock(leg.end()), leg.headingAtStart(), leg.maxOpposing(), leg.maxCross()));
        }
        double ferry = b.legs().stream().mapToDouble(Navigator.LegRun::maxFerryAngle).max().orElse(0);
        if (ferry >= 10) {
            out.append(String.format(Locale.ROOT, "%nYou'll angle up to %.0f° into the stream to hold your line (\"Steer\" is the heading at the start of each leg).%n", ferry));
        }
        return out.toString();
    }

    /**
     * One row per departure time tried: '#' a good departure, '-' within reach but over a limit,
     * '.' doesn't arrive. Below it, the stream at the reference station as + (flood) and - (ebb).
     */
    static String timeline(Plan plan, Planner.Result r) {
        StringBuilder row = new StringBuilder(), stream = new StringBuilder();
        Current c = new Current(plan.station().events());
        double peak = plan.station().events().stream().mapToDouble(e -> Math.abs(e.speed())).max().orElse(1);
        int stride = Math.max(1, (int) Math.ceil(r.trips().size() / 60.0));
        for (int i = 0; i < r.trips().size(); i += stride) {
            Navigator.Trip t = r.trips().get(i);
            boolean arrives = t.legs().stream().allMatch(Navigator.LegRun::ok) && t.legs().size() == plan.legs().size();
            row.append(t.ok() ? '#' : arrives ? '-' : '.');
            double v = c.at(t.departure());
            if (Double.isNaN(v)) stream.append(' ');
            else if (Math.abs(v) < 0.15 * peak) stream.append('0');
            else stream.append(v > 0 ? (v > 0.6 * peak ? 'F' : 'f') : (v < -0.6 * peak ? 'E' : 'e'));
        }
        String head = clock(plan.windowStart());
        String tail = clock(plan.windowEnd());
        String gap = " ".repeat(Math.max(1, row.length() - head.length() - tail.length()));
        return "Departure  " + row + "\n" + "Stream     " + stream + "\n" + "           " + head + gap + tail + "\n"
                + "           # good   - over a limit   . won't make it    stream at " + plan.station().name() + ": F/f flood, E/e ebb, 0 slack\n";
    }
}
