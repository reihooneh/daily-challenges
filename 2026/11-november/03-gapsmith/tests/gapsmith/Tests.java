package gapsmith;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/** A small test runner: each check prints on failure; the exit code says whether all passed. */
public final class Tests {
    private static int checks = 0, failed = 0;
    private static final PrintStream RESULTS = System.out;

    private static void check(boolean ok, String what) {
        checks++;
        if (!ok) {
            failed++;
            RESULTS.println("FAIL: " + what);
        }
    }

    static Layout layout(String text) {
        try {
            return Layout.parse(text);
        } catch (Layout.LayoutException e) {
            throw new AssertionError(e.getMessage());
        }
    }

    private static void rejects(String text, String fragment) {
        try {
            Layout.parse(text);
            check(false, "should reject: " + fragment);
        } catch (Layout.LayoutException e) {
            check(e.getMessage().contains(fragment), "message '" + e.getMessage() + "' should mention '" + fragment + "'");
            check(!e.getMessage().contains("SECRET") && !e.getMessage().contains("<"), "never echoes the input: " + e.getMessage());
        }
    }

    /** Every join outside the reversing sections must be satisfied by the wiring. */
    static boolean wiringHolds(Layout l, int[] pol) {
        for (Layout.Join j : l.joins) {
            int a = pol[j.a().section()];
            int b = pol[j.b().section()];
            if (a == 0 || b == 0) continue;
            if (j.same() ? a != b : a == b) return false;
        }
        return true;
    }

    static final String OVAL = """
            train 1 m
            track a 1 m
            track b 1 m
            track c 1 m
            track d 1 m
            join a.b b.a
            join b.b c.a
            join c.b d.a
            join d.b a.a
            """;

    static final String BALLOON = """
            train 1.5 m
            track main 2 m
            turnout t 20 cm
            track l1 1 m
            track l2 1 m
            track l3 1 m
            join main.b t.p
            join t.s l1.a
            join l1.b l2.a
            join l2.b l3.a
            join l3.b t.d
            """;

    /** A wye: three turnouts in a triangle, each leg a short track. Always a reversing layout. */
    static final String WYE = """
            train 0.8 m
            turnout x 20 cm
            turnout y 20 cm
            turnout z 20 cm
            track xy 1 m
            track yz 1 m
            track zx 1 m
            track tail 2 m
            join x.s xy.a
            join xy.b y.s
            join y.d yz.a
            join yz.b z.d
            join z.s zx.a
            join zx.b x.d
            join x.p tail.a
            """;

    // ---------- Brute force: the best plan over every subset of sections ----------

    record Score(int comps, int cuts, double length) {}

    static Score brute(Layout l) {
        int n = l.sections.size();
        var adj = Polarity.adjacency(l);
        Score best = null;
        for (int mask = 1; mask < (1 << n) - 1; mask++) {
            boolean[] in = new boolean[n];
            for (int i = 0; i < n; i++) in[i] = (mask >> i & 1) == 1;
            if (Polarity.colour(l, adj, in, null) == null) continue;
            // Components of the chosen sections.
            int[] comp = new int[n];
            java.util.Arrays.fill(comp, -1);
            int comps = 0;
            boolean ok = true;
            double total = 0;
            for (int s = 0; s < n && ok; s++) {
                if (!in[s] || comp[s] >= 0) continue;
                List<Integer> stack = new ArrayList<>(List.of(s));
                boolean[] part = new boolean[n];
                comp[s] = comps;
                double len = 0;
                int size = 0;
                while (!stack.isEmpty()) {
                    int u = stack.remove(stack.size() - 1);
                    part[u] = true;
                    len += l.sections.get(u).length();
                    size++;
                    for (int j : adj.get(u)) {
                        int v = l.joins.get(j).other(u);
                        if (in[v] && comp[v] < 0) {
                            comp[v] = comps;
                            stack.add(v);
                        }
                    }
                }
                if (len <= l.train || size > Planner.MAX_RUN || !Polarity.consistentWithin(l, adj, part)) ok = false;
                total += len;
                comps++;
            }
            if (!ok || comps > 2) continue;
            int cuts = 0;
            for (Layout.Join j : l.joins) if (in[j.a().section()] != in[j.b().section()]) cuts++;
            Score sc = new Score(comps, cuts, total);
            if (best == null || sc.comps() < best.comps() || (sc.comps() == best.comps() && sc.cuts() < best.cuts())
                    || (sc.comps() == best.comps() && sc.cuts() == best.cuts() && sc.comps() == 1 && sc.length() < best.length() - 1e-9)) {
                best = sc;
            }
        }
        return best;
    }

    static String randomLayout(Random r) {
        int n = 3 + r.nextInt(7);
        StringBuilder b = new StringBuilder("train " + (1 + r.nextInt(20)) / 10.0 + " m\n");
        List<String> ends = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            boolean turnout = r.nextInt(3) == 0;
            b.append(turnout ? "turnout " : "track ").append("s").append(i).append(' ').append(20 + r.nextInt(180)).append(" cm\n");
            if (turnout) for (String e : new String[] {"p", "s", "d"}) ends.add("s" + i + "." + e);
            else for (String e : new String[] {"a", "b"}) ends.add("s" + i + "." + e);
        }
        java.util.Collections.shuffle(ends, r);
        int joins = Math.min(ends.size() / 2, n + r.nextInt(3));
        for (int k = 0; k < joins; k++) b.append("join ").append(ends.get(2 * k)).append(' ').append(ends.get(2 * k + 1)).append('\n');
        return b.toString();
    }

    // ---------- Command line ----------

    static int cli(String input, String... args) {
        InputStream oldIn = System.in;
        PrintStream oldOut = System.out;
        PrintStream oldErr = System.err;
        ByteArrayOutputStream sink = new ByteArrayOutputStream();
        try {
            System.setIn(new ByteArrayInputStream(input.getBytes(StandardCharsets.UTF_8)));
            System.setOut(new PrintStream(sink, true, StandardCharsets.UTF_8));
            System.setErr(new PrintStream(sink, true, StandardCharsets.UTF_8));
            return Main.run(args);
        } finally {
            System.setIn(oldIn);
            System.setOut(oldOut);
            System.setErr(oldErr);
            lastOutput = sink.toString(StandardCharsets.UTF_8);
        }
    }

    static String lastOutput = "";

    public static void main(String[] args) throws IOException {
        // ---------- Reading layouts ----------
        Layout l = layout("layout Test\ntrain 45 cm\ntrack a 300 mm\nturnout t 0.2 m\njoin a.b t.p\n");
        check(Math.abs(l.train - 0.45) < 1e-12, "cm");
        check(Math.abs(l.sections.get(0).length() - 0.3) < 1e-12, "mm");
        check(l.joins.get(0).same(), "a track's end b to a turnout's points: rails continue");
        Layout k = layout("train 1 m\ntrack a 1 m\ntrack b 1 m\nturnout t 1 m\njoin a.b b.b\njoin t.s t.d\n");
        check(!k.joins.get(0).same(), "two b ends nose to nose: rails cross");
        check(!k.joins.get(1).same(), "a turnout's two frog ends joined: rails cross");

        rejects("", "no track");
        rejects("track a 1 m\n", "longest train");
        rejects("train 1 m\ntrack a 1 m\ntrack a 2 m\n", "already used");
        rejects("train 1 m\ntrack A 1 m\n", "ids are lower-case");
        rejects("train 1 m\ntrack a 1 km\n", "write lengths like");
        rejects("train 1 m\ntrack a 500 m\n", "1 cm to 100 m");
        rejects("train 1 m\ntrack a 1 m\njoin a.b b.a\n", "hasn't been listed");
        rejects("train 1 m\ntrack a 1 m\njoin a.b a.p\n", "track has ends a and b");
        rejects("train 1 m\nturnout t 1 m\ntrack a 1 m\njoin t.a a.a\n", "turnouts have ends p, s and d");
        rejects("train 1 m\ntrack a 1 m\ntrack b 1 m\ntrack c 1 m\njoin a.b b.a\njoin a.b c.a\n", "joined twice");
        rejects("train 1 m\ntrack a 1 m\njoin a.b a.b\n", "joined twice");
        rejects("train 1 m\ntrack a\u202eSECRET 1 m\n", "invisible formatting");
        rejects("train 1 m\ntrack a\u001b[2J 1 m\n", "control");
        rejects("layout <script>\ntrain 1 m\ntrack a 1 m\n", "layout name");
        rejects("train 1 m\nrm -rf SECRET\n", "lines start with");
        rejects("train 1 m\n# " + "x".repeat(300) + "\ntrack a 1 m\n", "longer than 200");
        rejects("#\n".repeat(40_000), "larger than 64 KB");
        StringBuilder many = new StringBuilder("train 1 m\n");
        for (int i = 0; i < 201; i++) many.append("track s").append(i).append(" 1 m\n");
        rejects(many.toString(), "at most 200 sections");

        // ---------- Polarity ----------
        Planner.Plan oval = Planner.plan(layout(OVAL));
        check(oval.alreadyFine() && oval.reversers().isEmpty() && wiringHolds(layout(OVAL), oval.polarity()), "an oval needs no cuts");

        Layout balloon = layout(BALLOON);
        Planner.Plan bp = Planner.plan(balloon);
        check(!bp.alreadyFine(), "a balloon loop is a short circuit");
        check(bp.loop().size() == 4, "the odd loop goes round the balloon (" + bp.loop() + ")");
        int crossings = 0;
        for (int j : bp.loop()) if (!balloon.joins.get(j).same()) crossings++;
        check(crossings % 2 == 1, "the loop has an odd number of crossings");
        check(bp.reversers().size() == 1, "one auto-reverser");
        Planner.Reverser r = bp.reversers().get(0);
        check(r.cuts().size() == 2, "two cuts");
        check(r.length() > balloon.train, "the section holds the longest train");
        check(wiringHolds(balloon, bp.polarity()), "the wiring outside the reversing section holds");
        for (int s : r.sections()) check(bp.polarity()[s] == 0, "reversing sections are fed by the reverser");

        Layout wye = layout(WYE);
        Planner.Plan wp = Planner.plan(wye);
        check(!wp.alreadyFine() && wp.reversers().size() == 1 && wiringHolds(wye, wp.polarity()), "a wye needs one reversing leg");

        Layout tooShort = layout(BALLOON.replace("train 1.5 m", "train 6 m"));
        Planner.Plan ts = Planner.plan(tooShort);
        check(ts.reversers().isEmpty() && ts.problem() != null && ts.problem().contains("longer than your longest train"), "a train longer than the loop can't be fixed: " + ts.problem());
        check(Report.render(tooShort, ts).contains("NO FIX FOUND"), "and the report says so");

        // ---------- Against every subset ----------
        Random rnd = new Random(42);
        int compared = 0, broken = 0;
        for (int round = 0; round < 400; round++) {
            Layout rl = layout(randomLayout(rnd));
            Planner.Plan p = Planner.plan(rl);
            if (p.alreadyFine()) {
                check(wiringHolds(rl, p.polarity()), "fine layouts wire consistently");
                continue;
            }
            broken++;
            Score want = brute(rl);
            if (want == null) {
                check(p.reversers().isEmpty(), "no plan exists, and none is claimed (round " + round + ")");
                continue;
            }
            check(!p.reversers().isEmpty(), "a plan exists and is found (round " + round + ")");
            if (p.reversers().isEmpty()) continue;
            int cuts = p.reversers().stream().mapToInt(x -> x.cuts().size()).sum();
            double len = p.reversers().stream().mapToDouble(Planner.Reverser::length).sum();
            check(p.reversers().size() == want.comps() && cuts == want.cuts(), "round " + round + ": " + p.reversers().size() + "/" + cuts + " vs " + want);
            if (want.comps() == 1) check(Math.abs(len - want.length()) < 1e-9, "round " + round + ": shortest section");
            check(wiringHolds(rl, p.polarity()), "round " + round + ": wiring holds");
            for (Planner.Reverser x : p.reversers()) check(x.length() > rl.train, "round " + round + ": holds the train");
            compared++;
        }
        check(broken > 60 && compared > 40, "enough short circuits were tested (" + broken + " broken, " + compared + " compared)");

        // ---------- Command line ----------
        Path dir = Files.createTempDirectory("gapsmith");
        try {
            Path ex = Path.of("examples/riverside.txt");
            check(cli("", ex.toString()) == 1 && lastOutput.contains("loop1.b / loop2.a"), "example: cuts found");
            String fromFile = lastOutput;
            check(cli(Files.readString(ex), "-") == 1 && lastOutput.equals(fromFile), "standard input gives the same");
            check(cli(OVAL, "-") == 0 && lastOutput.contains("No reversing loops"), "an oval exits 0");
            check(cli("", "a", "b") == 2 && cli("", "--help") == 2, "usage");
            check(cli("", dir.toString()) == 2 && lastOutput.contains("not a regular file"), "a folder is refused");
            Path link = dir.resolve("link.txt");
            Files.createSymbolicLink(link, ex.toAbsolutePath());
            check(cli("", link.toString()) == 2 && lastOutput.contains("symbolic link"), "a link is refused");
            check(cli("", "secret-name-zz.txt") == 2 && !lastOutput.contains("secret-name"), "the path isn't echoed");
            check(cli("#".repeat(100_000), "-") == 2 && lastOutput.contains("64 KB"), "big input refused");
            byte[] bad = {'t', 'r', (byte) 0xff, '\n'};
            Path badFile = dir.resolve("bad.txt");
            Files.write(badFile, bad);
            check(cli("", badFile.toString()) == 2 && lastOutput.contains("UTF-8"), "invalid UTF-8 refused");
        } finally {
            try (var s = Files.list(dir)) {
                for (Path p : s.toList()) Files.delete(p);
            }
            Files.delete(dir);
        }

        RESULTS.println(checks + " checks, " + failed + " failed");
        System.exit(failed == 0 ? 0 : 1);
    }
}
