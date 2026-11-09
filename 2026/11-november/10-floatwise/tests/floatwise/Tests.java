package floatwise;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/** A small test runner: no dependencies, run with {@code make test}. */
public final class Tests {

    private static int passed;
    private static int failed;

    interface Body {
        void run() throws Exception;
    }

    static void test(String name, Body body) {
        try {
            body.run();
            passed++;
            System.out.println("ok   " + name);
        } catch (Throwable t) {
            failed++;
            System.out.println("FAIL " + name + ": " + t);
        }
    }

    static void check(boolean ok, String what) {
        if (!ok) {
            throw new AssertionError(what);
        }
    }

    static Chart chart(String... lines) throws Chart.ChartException {
        return Chart.parse(String.join("\n", lines));
    }

    static void refused(String text, String expected) {
        try {
            Chart.parse(text);
            throw new AssertionError("accepted: " + expected);
        } catch (Chart.ChartException e) {
            check(e.getMessage().contains(expected), "message \"" + e.getMessage() + "\" should contain \"" + expected + "\"");
        }
    }

    static final String HEAD = "colour . cream\ncolour x navy\n";

    public static void main(String[] args) throws Exception {
        test("rows are stored bottom first and stitches counted from the right", () -> {
            Chart c = chart("title: Test", "colour . cream", "colour x navy", "chart:", "x.....", "......");
            check(c.height() == 2 && c.width() == 6, "size");
            check(c.rows().get(0).equals("......") && c.rows().get(1).equals("x....."), "bottom row is round 1");
            check(c.stitchNumber(0) == 6 && c.stitchNumber(5) == 1, "stitch numbers");
            check(c.rowName(1).equals("Round 2"), "round name");
        });

        test("bad charts are refused with a reason", () -> {
            refused(HEAD + "chart:\n..x\n..\n", "row is 2 stitches");
            refused(HEAD + "chart:\n..y\n", "uses a symbol with no colour");
            refused("colour . cream\nchart:\n..\n", "at least two colours");
            refused(HEAD, "no chart");
            refused(HEAD + "max-float: 1\nchart:\n..\n", "between 2 and 12");
            refused(HEAD + "max-float: 5\nmax-float: 6\nchart:\n..\n", "given twice");
            refused(HEAD + "colour . white\nchart:\n..\n", "already has a colour");
            refused(HEAD + "knit: sideways\nchart:\n..\n", "round");
            refused(HEAD + "pattern: x\nchart:\n..\n", "unknown setting");
            refused(HEAD + "title: <script>\nchart:\n..\n", "a title is");
            refused(HEAD + "colour y #12345\nchart:\n..\n", "colour name");
            refused(HEAD + "chart:\n" + ".".repeat(65) + "\n", "2-64 stitches");
            refused(HEAD + "chart:\n" + "..\n".repeat(Chart.MAX_ROWS + 1), "at most 200 rows");
            refused(HEAD + "title: a\u0007b\nchart:\n..\n", "control");
            refused(HEAD + "title: abc\u202edef\nchart:\n..\n", "invisible");
            refused("x".repeat(Chart.MAX_BYTES + 1), "larger than 64 KB");
        });

        test("floats wrap round the repeat when knitted in the round, not when flat", () -> {
            Chart round = chart(HEAD + "chart:\nxx......xx");
            List<Planner.Float> fs = new Planner(round).floats();
            // navy: from stitch col 1 to col 8 (6 cream between), then 8,9 -> 0 adjacent (wrap, no gap)
            check(fs.stream().anyMatch(f -> f.colour() == 'x' && f.length() == 6 && f.start() == 2), "navy float");
            // cream: 2..7, then wraps over 8,9,0,1: a 4-stitch float starting at col 8
            check(fs.stream().anyMatch(f -> f.colour() == '.' && f.length() == 4 && f.start() == 8), "cream wraps");
            Chart flat = chart(HEAD + "knit: flat\nchart:\nxx......xx");
            List<Planner.Float> ff = new Planner(flat).floats();
            check(ff.size() == 1 && ff.get(0).colour() == 'x' && ff.get(0).length() == 6, "flat: only the inner float");
            Chart lone = chart(HEAD + "chart:\n...x....");
            check(new Planner(lone).floats().stream().anyMatch(f -> f.colour() == 'x' && f.length() == 7), "a lone stitch floats all the way round");
            Chart solid = chart(HEAD + "chart:\n........");
            check(new Planner(solid).floats().isEmpty(), "a solid round has no floats");
        });

        test("the number of catches is the fewest possible, and every option is valid", () -> {
            for (int max = 2; max <= 12; max++) {
                for (int len = 1; len <= 40; len++) {
                    int k = Planner.catchesNeeded(len, max);
                    // brute force: the fewest catches such that the pieces fit
                    int best = 0;
                    while ((len - best) > max * (best + 1)) {
                        best++;
                    }
                    check(k == best, "catches for " + len + " at " + max);
                    if (len > 24) {
                        continue;
                    }
                    List<Planner.FloatOption> opts = Planner.floatOptions(len, max);
                    int brute = 0;
                    for (int mask = 0; mask < 1 << len; mask++) {
                        if (Integer.bitCount(mask) != k) {
                            continue;
                        }
                        int[] off = new int[k];
                        int n = 0;
                        for (int o = 0; o < len; o++) {
                            if ((mask >> o & 1) == 1) {
                                off[n++] = o;
                            }
                        }
                        boolean ok = true;
                        for (int p : Planner.pieces(off, len)) {
                            ok &= p <= max;
                        }
                        if (ok) {
                            brute++;
                        }
                    }
                    check(opts.size() == brute, "options for " + len + " at " + max + ": " + opts.size() + " vs " + brute);
                    for (Planner.FloatOption o : opts) {
                        for (int p : Planner.pieces(o.offsets(), len)) {
                            check(p <= max, "piece within the limit");
                        }
                    }
                }
            }
        });

        test("the plan is the best of every combination: checked by brute force", () -> {
            Random rng = new Random(7);
            int checkedCharts = 0;
            for (int t = 0; t < 150; t++) {
                Chart c = randomChart(rng, 3 + rng.nextInt(6), 2 + rng.nextInt(3), rng.nextBoolean());
                Planner p = new Planner(c);
                boolean[] exact = {true};
                List<List<Planner.RowOption>> rows = new ArrayList<>();
                long combos = 1;
                for (int r = 0; r < c.height(); r++) {
                    rows.add(p.rowOptions(r, exact));
                    combos *= rows.get(r).size();
                }
                if (combos > 20000 || !exact[0]) {
                    continue;
                }
                double best = bruteBest(p, rows, 0, new ArrayList<>());
                Planner.Plan plan = p.plan();
                check(Math.abs(plan.cost() - best) < 1e-9, "chart " + t + ": " + plan.cost() + " vs " + best);
                checkedCharts++;
            }
            check(checkedCharts > 100, "enough charts compared: " + checkedCharts);
        });

        test("every plan leaves no float longer than the limit, and beats even spacing", () -> {
            Random rng = new Random(99);
            for (int t = 0; t < 200; t++) {
                Chart c = randomChart(rng, 4 + rng.nextInt(40), 1 + rng.nextInt(12), rng.nextBoolean());
                Planner p = new Planner(c);
                Planner.Plan plan = p.plan();
                Planner.Plan even = p.evenlySpaced();
                check(plan.longestLeft() <= c.maxFloat(), "chart " + t + " leaves " + plan.longestLeft());
                check(even.longestLeft() <= c.maxFloat(), "even spacing is valid too");
                check(plan.catches().size() == even.catches().size(), "both use the fewest catches");
                check(plan.cost() <= even.cost() + 1e-9, "chart " + t + ": plan " + plan.cost() + " > even " + even.cost());
            }
        });

        test("a 64-stitch repeat wraps correctly at the last bit", () -> {
            String row = "x" + ".".repeat(62) + "x";
            Chart c = chart(HEAD + "max-float: 5\nchart:\n" + row + "\n" + row + "\n" + row);
            Planner p = new Planner(c);
            Planner.Plan plan = p.plan();
            check(plan.longestLeft() <= 5, "within the limit");
            check(plan.stacked() == 0, "no stacking");
            check(p.right(1L << 63) == 1L && p.left(1L) == 1L << 63, "rotation wraps");
        });

        test("the snowflake example: no stacked catches where even spacing stacks six", () -> {
            Chart c = Chart.parse(Files.readString(Path.of("examples/snowflake-yoke.txt")));
            Planner p = new Planner(c);
            Planner.Plan plan = p.plan();
            check(plan.stacked() == 0, "stacked " + plan.stacked());
            check(p.evenlySpaced().stacked() == 6, "even spacing stacks six");
            check(plan.exact(), "searched exactly");
        });

        test("the drawing escapes text and draws every catch", () -> {
            Chart c = chart(HEAD + "title: Fish & Chips 'n' (chips)\nchart:\nx.........\n");
            Planner.Plan plan = new Planner(c).plan();
            String svg = Report.svg(c, plan);
            check(svg.contains("Fish &amp; Chips &apos;n&apos;"), "escaped");
            check(!svg.contains("& C"), "no raw ampersand");
            check(svg.split("<circle", -1).length - 1 == plan.catches().size(), "one dot per catch");
            check(Report.xml("<a href=\"x\">").equals("&lt;a href=&quot;x&quot;&gt;"), "xml escaping");
        });

        test("command line: report, drawing and options", () -> {
            Path dir = Files.createTempDirectory("floatwise");
            try {
                Path svg = dir.resolve("band.svg");
                Result r = run("examples/snowflake-yoke.txt", "--svg", svg.toString());
                check(r.code == 0, r.err);
                check(r.out.contains("Floatwise: Snowflake band") && r.out.contains("0 stacked pairs"), r.out);
                check(Files.readString(svg).startsWith("<svg"), "drawing written");
                Result again = run("examples/snowflake-yoke.txt", "--svg", svg.toString());
                check(again.code == 1 && again.err.contains("already exists"), "never overwrites");
                Result tighter = run("examples/border-flat.txt", "--max-float", "3");
                check(tighter.code == 0 && tighter.out.contains("longest float allowed: 3"), tighter.err);
                check(run("--help").out.contains("usage: floatwise"), "help");
            } finally {
                deleteAll(dir);
            }
        });

        test("command line: broken and hostile input is refused without echoing it", () -> {
            Path dir = Files.createTempDirectory("floatwise");
            try {
                Path big = Files.writeString(dir.resolve("big.txt"), "x".repeat(Chart.MAX_BYTES + 5));
                Path binary = Files.write(dir.resolve("bin.txt"), new byte[] {'c', 'h', (byte) 0xff, (byte) 0xfe});
                Path secret = Files.writeString(dir.resolve("secret.txt"), "password=hunter2\n");
                Path link = dir.resolve("link.txt");
                Files.createSymbolicLink(link, secret);
                Files.createDirectory(dir.resolve("folder"));
                String[][] cases = {
                    {big.toString()}, {binary.toString()}, {secret.toString()}, {link.toString()},
                    {dir.resolve("folder").toString()}, {dir.resolve("missing.txt").toString()}, {},
                    {secret.toString(), "--max-float", "99"}, {secret.toString(), "--max-float", "4; rm -rf /"},
                    {secret.toString(), "--svg", "out.png"}, {secret.toString(), "--evil"},
                    {"examples/snowflake-yoke.txt", "--svg", dir.resolve("no/such/dir/x.svg").toString()},
                };
                String[] expect = {
                    "larger than 64 KB", "not valid UTF-8", "unknown setting", "regular file",
                    "regular file", "cannot open", "give a chart file",
                    "--max-float must be", "--max-float must be",
                    "ending in .svg", "unknown option",
                    "cannot write",
                };
                for (int i = 0; i < cases.length; i++) {
                    Result r = run(cases[i]);
                    check(r.code == 1, "case " + i + " exit " + r.code + " " + r.err);
                    check(r.err.contains(expect[i]), "case " + i + ": " + r.err);
                    check(!r.err.contains("hunter2"), "case " + i + " echoed the file");
                }
            } finally {
                deleteAll(dir);
            }
        });

        System.out.println(passed + " passed, " + failed + " failed");
        if (failed > 0) {
            System.exit(1);
        }
    }

    record Result(int code, String out, String err) {}

    static Result run(String... args) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        int code = Main.run(args, new PrintStream(out, true, StandardCharsets.UTF_8), new PrintStream(err, true, StandardCharsets.UTF_8));
        return new Result(code, out.toString(StandardCharsets.UTF_8), err.toString(StandardCharsets.UTF_8));
    }

    static Chart randomChart(Random rng, int width, int height, boolean round) throws Chart.ChartException {
        StringBuilder s = new StringBuilder("colour . cream\ncolour x navy\ncolour o red\n");
        s.append("knit: ").append(round ? "round" : "flat").append('\n');
        s.append("max-float: ").append(2 + rng.nextInt(4)).append('\n');
        s.append("chart:\n");
        for (int r = 0; r < height; r++) {
            for (int c = 0; c < width; c++) {
                double v = rng.nextDouble();
                s.append(v < 0.65 ? '.' : v < 0.93 ? 'x' : 'o');
            }
            s.append('\n');
        }
        return Chart.parse(s.toString());
    }

    static double bruteBest(Planner p, List<List<Planner.RowOption>> rows, int r, List<Planner.RowOption> acc) {
        if (r == rows.size()) {
            return p.describe(acc, true).cost();
        }
        double best = Double.POSITIVE_INFINITY;
        for (Planner.RowOption o : rows.get(r)) {
            acc.add(o);
            best = Math.min(best, bruteBest(p, rows, r + 1, acc));
            acc.remove(acc.size() - 1);
        }
        return best;
    }

    static void deleteAll(Path dir) throws java.io.IOException {
        try (var walk = Files.walk(dir)) {
            for (Path p : walk.sorted(java.util.Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(p);
            }
        }
    }
}
