package floatwise;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/**
 * Finds the floats in a chart and chooses where to catch the long ones.
 *
 * <p>Every float longer than the limit gets the fewest catches that bring each piece within it.
 * Where those catches go is chosen for the whole chart at once: a catch directly above or below
 * another in the next round shows through as a little vertical line, so the planner runs a
 * dynamic programme over the rows, where each row's state is the set of columns it catches in.
 */
public final class Planner {

    /** A strand of one colour carried behind {@code length} stitches, starting at {@code start}. */
    public record Float(int row, char colour, int start, int length) {}

    /** A catch: the strand of {@code colour} is trapped behind the stitch in {@code column}. */
    public record Catch(int row, int column, char colour) {}

    /** The catches for a chart, with the numbers that describe how good they are. */
    public record Plan(List<Catch> catches, double cost, int stacked, int diagonal, int longestLeft, boolean exact) {}

    /** Costs, in arbitrary units: what each kind of untidiness is worth avoiding. */
    static final double STACKED = 10;
    static final double DIAGONAL = 2;
    static final double SAME_ROW_NEIGHBOURS = 1;
    static final double SAME_STITCH = 3;
    static final double UNEVEN = 0.25;
    static final double AT_A_CHANGE = 0.5;

    /** Most ways of catching one row that the search will consider. */
    static final int ROW_CAP = 400;

    private final Chart chart;
    private final int width;
    private final long full;

    public Planner(Chart chart) {
        this.chart = chart;
        this.width = chart.width();
        this.full = width == 64 ? -1L : (1L << width) - 1;
    }

    /** Every float in the chart, row by row (bottom first), colour by colour. */
    public List<Float> floats() {
        List<Float> out = new ArrayList<>();
        for (int r = 0; r < chart.height(); r++) {
            out.addAll(floatsInRow(r));
        }
        return out;
    }

    List<Float> floatsInRow(int r) {
        List<Float> out = new ArrayList<>();
        for (char colour : symbolsIn(r)) {
            List<Integer> at = new ArrayList<>();
            for (int c = 0; c < width; c++) {
                if (chart.at(r, c) == colour) {
                    at.add(c);
                }
            }
            if (at.size() == width) {
                continue;
            }
            if (chart.inTheRound()) {
                // In the round the row repeats, so the strand runs from the last stitch of one
                // repeat into the next: the gaps are cyclic.
                for (int i = 0; i < at.size(); i++) {
                    int cur = at.get(i);
                    int next = at.get((i + 1) % at.size());
                    int gap = Math.floorMod(next - cur - 1, width);
                    if (at.size() == 1) {
                        gap = width - 1;
                    }
                    if (gap > 0) {
                        out.add(new Float(r, colour, (cur + 1) % width, gap));
                    }
                }
            } else {
                for (int i = 0; i + 1 < at.size(); i++) {
                    int gap = at.get(i + 1) - at.get(i) - 1;
                    if (gap > 0) {
                        out.add(new Float(r, colour, at.get(i) + 1, gap));
                    }
                }
            }
        }
        return out;
    }

    private List<Character> symbolsIn(int r) {
        List<Character> out = new ArrayList<>();
        for (int c = 0; c < width; c++) {
            char s = chart.at(r, c);
            if (!out.contains(s)) {
                out.add(s);
            }
        }
        return out;
    }

    /** The fewest catches that leave every piece of a float of this length within the limit. */
    static int catchesNeeded(int length, int max) {
        // k catches leave length - k stitches in k + 1 pieces of at most max: k >= (length - max) / (max + 1).
        return length <= max ? 0 : length / (max + 1);
    }

    /** One way to catch one float: the offsets of its catches, and what it costs on its own. */
    record FloatOption(int[] offsets, double cost) {}

    /** Every way to catch a float with the fewest catches. */
    static List<FloatOption> floatOptions(int length, int max) {
        int k = catchesNeeded(length, max);
        List<FloatOption> out = new ArrayList<>();
        if (k == 0) {
            out.add(new FloatOption(new int[0], 0));
            return out;
        }
        int[] offsets = new int[k];
        fill(offsets, 0, 0, length, max, out);
        return out;
    }

    private static void fill(int[] offsets, int i, int from, int length, int max, List<FloatOption> out) {
        if (i == offsets.length) {
            int last = length - 1 - offsets[i - 1];
            if (last > max) {
                return;
            }
            out.add(new FloatOption(offsets.clone(), floatCost(offsets, length)));
            return;
        }
        // The piece before this catch must be within the limit.
        for (int o = from; o < length && o - from <= max; o++) {
            offsets[i] = o;
            fill(offsets, i + 1, o + 1, length, max, out);
        }
    }

    static double floatCost(int[] offsets, int length) {
        int[] pieces = pieces(offsets, length);
        int lo = Arrays.stream(pieces).min().orElse(0);
        int hi = Arrays.stream(pieces).max().orElse(0);
        long atChange = Arrays.stream(pieces).filter(p -> p == 0).count();
        return UNEVEN * (hi - lo) + AT_A_CHANGE * atChange;
    }

    /** The lengths of the pieces a float is cut into by catches at these offsets. */
    static int[] pieces(int[] offsets, int length) {
        int[] out = new int[offsets.length + 1];
        int from = 0;
        for (int i = 0; i < offsets.length; i++) {
            out[i] = offsets[i] - from;
            from = offsets[i] + 1;
        }
        out[offsets.length] = length - from;
        return out;
    }

    /** One way to catch a whole row. */
    record RowOption(long mask, List<Catch> catches, double cost) {}

    /** The ways to catch a row; {@code exact[0]} is cleared if some had to be left out. */
    List<RowOption> rowOptions(int r, boolean[] exact) {
        List<Float> fs = new ArrayList<>();
        List<List<FloatOption>> choices = new ArrayList<>();
        for (Float f : floatsInRow(r)) {
            if (f.length() > chart.maxFloat()) {
                List<FloatOption> opts = new ArrayList<>(floatOptions(f.length(), chart.maxFloat()));
                opts.sort(Comparator.comparingDouble(FloatOption::cost));
                fs.add(f);
                choices.add(opts);
            }
        }
        // Too many combinations: keep each float's best few until the row fits the cap.
        while (product(choices) > ROW_CAP) {
            exact[0] = false;
            List<FloatOption> biggest = choices.stream().max(Comparator.comparingInt(List::size)).orElseThrow();
            biggest.subList(Math.max(1, biggest.size() / 2), biggest.size()).clear();
        }
        List<RowOption> out = new ArrayList<>();
        combine(fs, choices, 0, new ArrayList<>(), 0, out);
        return out;
    }

    private static long product(List<List<FloatOption>> choices) {
        long p = 1;
        for (List<FloatOption> c : choices) {
            p = Math.min(Long.MAX_VALUE / 1024, p * c.size());
        }
        return p;
    }

    private void combine(List<Float> fs, List<List<FloatOption>> choices, int i, List<Catch> acc, double cost, List<RowOption> out) {
        if (i == fs.size()) {
            long mask = 0;
            int same = 0;
            for (Catch c : acc) {
                long bit = 1L << c.column();
                if ((mask & bit) != 0) {
                    same++;
                }
                mask |= bit;
            }
            double total = cost + SAME_STITCH * same + SAME_ROW_NEIGHBOURS * Long.bitCount(mask & right(mask));
            out.add(new RowOption(mask, List.copyOf(acc), total));
            return;
        }
        Float f = fs.get(i);
        for (FloatOption o : choices.get(i)) {
            int before = acc.size();
            for (int off : o.offsets()) {
                acc.add(new Catch(f.row(), columnOf(f, off), f.colour()));
            }
            combine(fs, choices, i + 1, acc, cost + o.cost(), out);
            acc.subList(before, acc.size()).clear();
        }
    }

    int columnOf(Float f, int offset) {
        return chart.inTheRound() ? (f.start() + offset) % width : f.start() + offset;
    }

    /** Each catch column moved one stitch to the right (wrapping round in the round). */
    long right(long m) {
        if (chart.inTheRound()) {
            return ((m << 1) | (m >>> (width - 1))) & full;
        }
        return (m << 1) & full;
    }

    long left(long m) {
        if (chart.inTheRound()) {
            return ((m >>> 1) | (m << (width - 1))) & full;
        }
        return m >>> 1;
    }

    /** The cost between two neighbouring rows' catches. */
    double between(long below, long above) {
        return STACKED * Long.bitCount(below & above)
                + DIAGONAL * (Long.bitCount(above & right(below)) + Long.bitCount(above & left(below)));
    }

    /** The best catches for the whole chart. */
    public Plan plan() {
        boolean[] exact = {true};
        int h = chart.height();
        List<List<RowOption>> rows = new ArrayList<>();
        for (int r = 0; r < h; r++) {
            rows.add(rowOptions(r, exact));
        }
        double[] best = new double[rows.get(0).size()];
        List<int[]> back = new ArrayList<>();
        for (int i = 0; i < best.length; i++) {
            best[i] = rows.get(0).get(i).cost();
        }
        back.add(new int[best.length]);
        for (int r = 1; r < h; r++) {
            List<RowOption> prev = rows.get(r - 1);
            List<RowOption> cur = rows.get(r);
            double[] next = new double[cur.size()];
            int[] from = new int[cur.size()];
            for (int j = 0; j < cur.size(); j++) {
                double b = Double.POSITIVE_INFINITY;
                for (int i = 0; i < prev.size(); i++) {
                    double v = best[i] + between(prev.get(i).mask(), cur.get(j).mask());
                    if (v < b - 1e-12) {
                        b = v;
                        from[j] = i;
                    }
                }
                next[j] = b + cur.get(j).cost();
            }
            best = next;
            back.add(from);
        }
        int pick = 0;
        for (int j = 1; j < best.length; j++) {
            if (best[j] < best[pick] - 1e-12) {
                pick = j;
            }
        }
        RowOption[] chosen = new RowOption[h];
        for (int r = h - 1; r >= 0; r--) {
            chosen[r] = rows.get(r).get(pick);
            pick = back.get(r)[pick];
        }
        return describe(Arrays.asList(chosen), exact[0]);
    }

    /** The usual habit: space each long float's catches evenly, ignoring the rows around it. */
    public Plan evenlySpaced() {
        List<RowOption> chosen = new ArrayList<>();
        for (int r = 0; r < chart.height(); r++) {
            List<Float> fs = new ArrayList<>();
            List<List<FloatOption>> choices = new ArrayList<>();
            for (Float f : floatsInRow(r)) {
                int k = catchesNeeded(f.length(), chart.maxFloat());
                if (k == 0) {
                    continue;
                }
                int[] offsets = new int[k];
                for (int i = 1; i <= k; i++) {
                    offsets[i - 1] = (int) Math.round((double) i * (f.length() + 1) / (k + 1)) - 1;
                }
                fs.add(f);
                choices.add(List.of(new FloatOption(offsets, floatCost(offsets, f.length()))));
            }
            List<RowOption> one = new ArrayList<>();
            combine(fs, choices, 0, new ArrayList<>(), 0, one);
            chosen.add(one.get(0));
        }
        return describe(chosen, true);
    }

    /** Scores any set of catches: used for both plans and by the tests. */
    Plan describe(List<RowOption> chosen, boolean exact) {
        List<Catch> all = new ArrayList<>();
        double cost = 0;
        int stacked = 0;
        int diagonal = 0;
        for (int r = 0; r < chosen.size(); r++) {
            RowOption o = chosen.get(r);
            all.addAll(o.catches());
            cost += o.cost();
            if (r > 0) {
                long below = chosen.get(r - 1).mask();
                cost += between(below, o.mask());
                stacked += Long.bitCount(below & o.mask());
                diagonal += Long.bitCount(o.mask() & right(below)) + Long.bitCount(o.mask() & left(below));
            }
        }
        return new Plan(List.copyOf(all), cost, stacked, diagonal, longestLeft(all), exact);
    }

    /** The longest stretch any strand still floats once these catches are made. */
    int longestLeft(List<Catch> catches) {
        int longest = 0;
        for (Float f : floats()) {
            List<Integer> offs = new ArrayList<>();
            for (Catch c : catches) {
                if (c.row() == f.row() && c.colour() == f.colour()) {
                    int off = chart.inTheRound() ? Math.floorMod(c.column() - f.start(), width) : c.column() - f.start();
                    if (off >= 0 && off < f.length()) {
                        offs.add(off);
                    }
                }
            }
            int[] o = offs.stream().mapToInt(Integer::intValue).sorted().toArray();
            for (int p : pieces(o, f.length())) {
                longest = Math.max(longest, p);
            }
        }
        return longest;
    }
}
