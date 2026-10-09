package changeling;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * changeling [--days N] [--seed N] STALL_FILE    (use - for standard input)
 *
 * Exit codes: 0 the float covers the day, 1 customers will still be stuck (more than
 * one every two days), 2 the input could not be used.
 */
public final class Main {
    static final String USAGE = "usage: changeling [--days 50-1000] [--seed N] STALL_FILE   (use - for standard input)";

    private Main() {}

    public static void main(String[] args) {
        System.exit(run(args, System.in, System.out, System.err));
    }

    /** A price change worth suggesting, with what it does to the float and the risk. */
    record Nudge(String item, long from, long to, double stuckBefore, double stuckAfter, long floatAfter) {}

    static int run(String[] args, InputStream stdin, PrintStream out, PrintStream err) {
        String path = null;
        int dayCount = 100;
        long seed = 26;
        try {
            for (int i = 0; i < args.length; i++) {
                switch (args[i]) {
                    case "--days" -> dayCount = option(args, ++i, 50, 1000, "--days must be a whole number from 50 to 1000");
                    case "--seed" -> seed = option(args, ++i, 0, 99_999, "--seed must be a whole number from 0 to 99999");
                    case "-h", "--help" -> {
                        out.println(USAGE);
                        return 0;
                    }
                    default -> {
                        if (args[i].startsWith("-") && !args[i].equals("-")) throw new InputException(0, "unknown option");
                        if (path != null) throw new InputException(0, "give exactly one stall file");
                        path = args[i];
                    }
                }
            }
            if (path == null) throw new InputException(0, "give a stall file");
            Stall stall = Stall.parse(read(path, stdin));
            dayCount = Simulator.daysFor(dayCount, stall.customers);
            double stuck = report(stall, dayCount, seed, out);
            return stuck > 0.5 ? 1 : 0;
        } catch (InputException e) {
            err.println("changeling: " + e.getMessage());
            err.println(USAGE);
            return 2;
        }
    }

    private static int option(String[] args, int i, int lo, int hi, String message) throws InputException {
        if (i >= args.length || !args[i].matches("\\d{1,5}")) throw new InputException(0, message);
        int v = Integer.parseInt(args[i]);
        if (v < lo || v > hi) throw new InputException(0, message);
        return v;
    }

    /** Reads at most 64 KB plus one byte, so a huge file or endless stream is refused, not loaded. */
    static String read(String path, InputStream stdin) throws InputException {
        byte[] bytes;
        try (InputStream in = path.equals("-") ? stdin : Files.newInputStream(Path.of(path))) {
            bytes = in.readNBytes(Stall.MAX_BYTES + 1);
        } catch (IOException | RuntimeException e) {
            throw new InputException(0, "the stall file could not be read");
        }
        if (bytes.length > Stall.MAX_BYTES) throw new InputException(0, "the stall file is larger than 64 KB");
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString();
        } catch (CharacterCodingException e) {
            throw new InputException(0, "the stall file is not valid UTF-8 text");
        }
    }

    /** Prints the report and returns the expected stuck customers per day with the recommended float. */
    static double report(Stall stall, int dayCount, long seed, PrintStream out) {
        Simulator sim = new Simulator(stall, dayCount, seed);
        int[] plan = Planner.plan(sim, stall.budget);
        Simulator.Result mine = sim.run(plan);
        int[] typical = Planner.typical(stall.budget);
        Simulator.Result theirs = sim.run(typical);

        out.println("CHANGELING  " + stall.title);
        out.printf("%d cash customers a day, float budget %s, tested on %d simulated days%n%n",
                stall.customers, Money.format(stall.budget), dayCount);

        out.println("RECOMMENDED FLOAT  (" + Money.format(Planner.value(plan)) + ")");
        for (int i = 0; i < Planner.FLOAT_DENOMS; i++) {
            if (plan[i] == 0) continue;
            String unit = rolls(i, plan[i]);
            out.printf("  %-4s x %-4d %-14s %9s%n", Money.name(i), plan[i], unit, Money.format((long) plan[i] * Money.DENOMS[i]));
        }
        if (Planner.value(plan) < stall.budget)
            out.println("  (The rest of the budget wouldn't reduce the risk, so leave it at home.)");

        out.println();
        out.println("RISK                                   this float     typical float*");
        out.printf("  Customers you can't give change to   %-14s %s%n", perDay(mine.stuckPerDay()), perDay(theirs.stuckPerDay()));
        out.printf("  Days with at least one stuck sale    %-14s %s%n", pct(mine.daysWithStuck()), pct(theirs.daysWithStuck()));
        out.printf("  Sales lost for want of change        %-14s %s%n", Money.format(Math.round(mine.lostPerDay())) + " a day",
                Money.format(Math.round(theirs.lostPerDay())) + " a day");
        out.println("  * the same budget split evenly across 50c, $1, $2, $5 and $10");
        String shortages = shortages(mine.shortBy());
        if (!shortages.isEmpty()) out.println("  When it does go wrong, you're short of: " + shortages);

        int[] quick = Planner.plan(sim, stall.budget, false);
        List<Nudge> nudges = nudges(stall, dayCount, seed, sim.run(quick).stuckPerDay(), Planner.value(quick));
        if (!nudges.isEmpty()) {
            out.println();
            out.println("PRICE NUDGES  (fewer awkward amounts, so fewer coins needed)");
            for (Nudge n : nudges)
                out.printf("  %-14s %s -> %s   stuck customers %s -> %s, float needed %s%n", n.item(), Money.format(n.from()), Money.format(n.to()),
                        perDayShort(n.stuckBefore()), perDayShort(n.stuckAfter()), Money.format(n.floatAfter()));
        }
        return mine.stuckPerDay();
    }

    /**
     * For the three best-selling items, try nearby round prices. A nudge is reported only if,
     * with a float re-planned for the new price, it removes stuck customers or lets a smaller
     * float do the same job.
     */
    static List<Nudge> nudges(Stall stall, int dayCount, long seed, double stuckNow, long floatNow) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < stall.items.size(); i++) order.add(i);
        order.sort(Comparator.comparingInt((Integer i) -> -stall.items.get(i).weight()));
        List<Nudge> found = new ArrayList<>();
        for (int idx : order.subList(0, Math.min(3, order.size()))) {
            Stall.Item it = stall.items.get(idx);
            Nudge best = null;
            for (long candidate : candidates(it.cents())) {
                Stall trial = stall.withPrice(idx, candidate);
                Simulator sim = new Simulator(trial, dayCount, seed);
                int[] f = Planner.plan(sim, stall.budget, false);
                double s = sim.run(f).stuckPerDay();
                long v = Planner.value(f);
                boolean better = s < stuckNow - 0.05 || (s <= stuckNow + 1e-9 && v < floatNow * 0.8);
                if (better && (best == null || s < best.stuckAfter() || (s == best.stuckAfter() && v < best.floatAfter())))
                    best = new Nudge(it.name(), it.cents(), candidate, stuckNow, s, v);
            }
            if (best != null) found.add(best);
        }
        return found;
    }

    /** Nearby round prices: the whole dollars either side, and the multiples of $5 if close. */
    static List<Long> candidates(long cents) {
        List<Long> out = new ArrayList<>();
        long down = cents / 100 * 100;
        long up = (cents + 99) / 100 * 100;
        for (long c : new long[] {down, up, cents / 500 * 500, (cents + 499) / 500 * 500})
            if (c > 0 && c != cents && Math.abs(c - cents) <= Math.max(100, cents / 4) && !out.contains(c)) out.add(c);
        return out;
    }

    /** "2 rolls + 5", "1 roll", "15 loose" for coins; "notes" for notes. */
    static String rolls(int denomIndex, int count) {
        int size = Money.ROLL[denomIndex];
        if (size == 0) return "notes";
        int r = count / size;
        int loose = count % size;
        if (r == 0) return loose + " loose";
        String s = r + (r == 1 ? " roll" : " rolls");
        return loose == 0 ? s : s + " + " + loose;
    }

    static String shortages(int[] shortBy) {
        int total = 0;
        for (int s : shortBy) total += s;
        if (total == 0) return "";
        List<Integer> idx = new ArrayList<>();
        for (int i = 0; i < shortBy.length; i++) if (shortBy[i] > 0) idx.add(i);
        idx.sort(Comparator.comparingInt((Integer i) -> -shortBy[i]));
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < Math.min(3, idx.size()); k++) {
            int i = idx.get(k);
            if (k > 0) sb.append(", ");
            sb.append(Money.name(i)).append(" (").append(Math.round(100.0 * shortBy[i] / total)).append("%)");
        }
        return sb.toString();
    }

    static String perDay(double v) {
        if (v == 0) return "none";
        return String.format("%.2f a day", v);
    }

    static String perDayShort(double v) {
        return v == 0 ? "0" : String.format("%.2f", v);
    }

    static String pct(double v) {
        return String.format("%.0f%%", v * 100);
    }
}
