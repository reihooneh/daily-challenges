package floatwise;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/** Writes a plan for a knitter: the chart with its catches, a summary, and round-by-round notes. */
public final class Report {

    private Report() {}

    public static String text(Chart chart, Planner.Plan plan, Planner.Plan even, List<Planner.Float> floats) {
        StringBuilder out = new StringBuilder();
        int w = chart.width();
        out.append("Floatwise: ").append(chart.title()).append('\n');
        out.append(chart.inTheRound()
                        ? "Knitted in the round · " + w + "-stitch repeat" + (chart.repeats() > 1 ? " × " + chart.repeats() : "")
                        : "Knitted flat · " + w + " stitches")
                .append(" · longest float allowed: ").append(chart.maxFloat()).append(" stitches\n\n");

        boolean[][] caught = new boolean[chart.height()][w];
        for (Planner.Catch c : plan.catches()) {
            caught[c.row()][c.column()] = true;
        }
        String unit = chart.inTheRound() ? "Round" : "Row";
        int label = Math.max(unit.length() + 1, String.valueOf(chart.height()).length());
        out.append("  ").append(pad(unit, label)).append(pad("Chart", w + 4)).append("Catches (*)\n");
        for (int r = chart.height() - 1; r >= 0; r--) {
            StringBuilder marks = new StringBuilder();
            for (int c = 0; c < w; c++) {
                marks.append(caught[r][c] ? '*' : '·');
            }
            out.append("  ").append(pad(String.valueOf(r + 1), label)).append(pad(chart.rows().get(r), w + 4)).append(marks).append('\n');
        }
        out.append('\n');

        List<Planner.Float> longOnes = floats.stream().filter(f -> f.length() > chart.maxFloat()).toList();
        if (longOnes.isEmpty()) {
            out.append("No float is longer than ").append(chart.maxFloat()).append(" stitches: nothing needs catching.\n");
            return out.toString();
        }
        Planner.Float longest = longOnes.stream().max((a, b) -> Integer.compare(a.length(), b.length())).orElseThrow();
        out.append("Floats over ").append(chart.maxFloat()).append(" stitches: ").append(longOnes.size())
                .append(" (longest ").append(longest.length()).append(", ")
                .append(name(chart, longest.colour())).append(", ").append(chart.rowName(longest.row()).toLowerCase(java.util.Locale.ROOT)).append(")\n");
        out.append("This plan: ").append(plan.catches().size()).append(chart.inTheRound() ? " catches per repeat, " : " catches, ")
                .append(count(plan.stacked(), "stacked pair")).append(", ")
                .append(count(plan.diagonal(), "diagonal neighbour")).append(", longest float left ")
                .append(plan.longestLeft()).append(" stitches.\n");
        out.append("Catching each float evenly instead: ")
                .append(count(even.stacked(), "stacked pair")).append(", ")
                .append(count(even.diagonal(), "diagonal neighbour")).append(".\n");
        if (!plan.exact()) {
            out.append("(Some rows had very many choices; the best few for each float were compared.)\n");
        }

        out.append('\n').append(unit).append(" by ").append(unit.toLowerCase(java.util.Locale.ROOT))
                .append(" (stitches counted from the right of the ").append(chart.inTheRound() ? "repeat" : "row").append("):\n");
        Map<Integer, Map<Character, List<Integer>>> byRow = new TreeMap<>();
        for (Planner.Catch c : plan.catches()) {
            byRow.computeIfAbsent(c.row(), k -> new TreeMap<>())
                    .computeIfAbsent(c.colour(), k -> new ArrayList<>())
                    .add(chart.stitchNumber(c.column()));
        }
        byRow.forEach((row, colours) -> {
            List<String> parts = new ArrayList<>();
            colours.forEach((colour, stitches) -> {
                stitches.sort(Integer::compare);
                parts.add("catch " + name(chart, colour) + " behind " + (stitches.size() == 1 ? "stitch " : "stitches ") + join(stitches));
            });
            out.append("  ").append(chart.rowName(row)).append(": ").append(String.join("; ", parts)).append('\n');
        });
        return out.toString();
    }

    /** A drawing of the chart with its catches, as a standalone SVG file. */
    public static String svg(Chart chart, Planner.Plan plan) {
        int cell = 18;
        int w = chart.width();
        int h = chart.height();
        int left = 40;
        int top = 48;
        int width = Math.max(320, left + w * cell + 24);
        int height = top + h * cell + 62;
        StringBuilder s = new StringBuilder();
        s.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"").append(width).append("\" height=\"").append(height)
                .append("\" viewBox=\"0 0 ").append(width).append(' ').append(height).append("\" font-family=\"sans-serif\">\n");
        s.append("<title>").append(xml(chart.title())).append("</title>\n");
        s.append("<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n");
        s.append("<text x=\"").append(left).append("\" y=\"28\" font-size=\"16\" fill=\"#222\">").append(xml(chart.title())).append("</text>\n");
        for (int r = 0; r < h; r++) {
            int y = top + (h - 1 - r) * cell;
            for (int c = 0; c < w; c++) {
                String fill = chart.colours().get(chart.at(r, c)).hex();
                s.append("<rect x=\"").append(left + c * cell).append("\" y=\"").append(y).append("\" width=\"").append(cell)
                        .append("\" height=\"").append(cell).append("\" fill=\"").append(fill).append("\" stroke=\"#999\" stroke-width=\"0.5\"/>\n");
            }
            if ((r + 1) % 5 == 0 || r == 0) {
                s.append("<text x=\"").append(left - 6).append("\" y=\"").append(y + cell - 5)
                        .append("\" font-size=\"10\" text-anchor=\"end\" fill=\"#555\">").append(r + 1).append("</text>\n");
            }
        }
        for (Planner.Catch c : plan.catches()) {
            int cx = left + c.column() * cell + cell / 2;
            int cy = top + (h - 1 - c.row()) * cell + cell / 2;
            String ink = chart.colours().get(c.colour()).hex();
            s.append("<circle cx=\"").append(cx).append("\" cy=\"").append(cy).append("\" r=\"5\" fill=\"").append(ink)
                    .append("\" stroke=\"#000\" stroke-width=\"1.5\"/>\n");
        }
        s.append("<text x=\"").append(left).append("\" y=\"").append(top + h * cell + 24)
                .append("\" font-size=\"11\" fill=\"#444\">Ringed dot: catch the strand of the dot's colour here.</text>\n");
        s.append("<text x=\"").append(left).append("\" y=\"").append(top + h * cell + 40)
                .append("\" font-size=\"11\" fill=\"#444\">").append(plan.catches().size()).append(" catches, ")
                .append(plan.stacked()).append(" stacked above one another.</text>\n");
        s.append("</svg>\n");
        return s.toString();
    }

    static String xml(String text) {
        StringBuilder out = new StringBuilder();
        for (char c : text.toCharArray()) {
            switch (c) {
                case '<' -> out.append("&lt;");
                case '>' -> out.append("&gt;");
                case '&' -> out.append("&amp;");
                case '"' -> out.append("&quot;");
                case '\'' -> out.append("&apos;");
                default -> out.append(c);
            }
        }
        return out.toString();
    }

    private static String name(Chart chart, char symbol) {
        return chart.colours().get(symbol).name();
    }

    private static String count(int n, String what) {
        return n + " " + what + (n == 1 ? "" : "s");
    }

    private static String join(List<Integer> xs) {
        List<String> s = xs.stream().map(String::valueOf).toList();
        if (s.size() == 1) {
            return s.get(0);
        }
        return String.join(", ", s.subList(0, s.size() - 1)) + " and " + s.get(s.size() - 1);
    }

    private static String pad(String s, int width) {
        return s.length() >= width ? s + " " : s + " ".repeat(width - s.length());
    }
}
