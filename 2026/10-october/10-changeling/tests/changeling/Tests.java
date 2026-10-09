package changeling;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.SplittableRandom;

/** A small self-contained test runner: no test framework to download. */
public final class Tests {
    private static int passed = 0;
    private static int failed = 0;

    private static void check(String name, boolean ok) {
        if (ok) passed++;
        else {
            failed++;
            System.out.println("FAIL " + name);
        }
    }

    public static void main(String[] args) throws Exception {
        money();
        drawer();
        drawerAgainstBruteForce();
        simulator();
        planner();
        stallParsing();
        nudges();
        commandLine();
        System.out.println(passed + " checks passed, " + failed + " failed");
        if (failed > 0) System.exit(1);
    }

    // ---------- Money ----------
    static void money() {
        check("parse 4.50", Money.parse("4.50") == 450);
        check("parse $4.5", Money.parse("$4.5") == 450);
        check("parse 4", Money.parse("4") == 400);
        for (String bad : new String[] {"4.505", "-1", "1e3", "4,50", "", " 4", "12345", "٤", "NaN", "4.5.0"})
            check("parse rejects [" + bad + "]", Money.parse(bad) == -1);
        // Australian cash rounding: 1-2c down, 3-4c up, 6-7c down, 8-9c up.
        long[][] rounding = {{101, 100}, {102, 100}, {103, 105}, {104, 105}, {105, 105}, {106, 105}, {107, 105}, {108, 110}, {109, 110}};
        for (long[] r : rounding) check("round " + r[0], Money.roundCash(r[0]) == r[1]);
        check("format", Money.format(1234).equals("$12.34") && Money.format(5).equals("$0.05"));
        check("names", Money.name(0).equals("5c") && Money.name(5).equals("$2") && Money.name(8).equals("$20"));
    }

    // ---------- Drawer ----------
    static int[] drawerOf(int... pairs) {
        int[] f = new int[Money.DENOMS.length];
        for (int i = 0; i < pairs.length; i += 2) f[Money.indexOf(pairs[i])] = pairs[i + 1];
        return f;
    }

    static void drawer() {
        Drawer d = new Drawer(drawerOf(1000, 1, 500, 1, 200, 2, 100, 1));
        check("biggest first: $16 = $10 + $5 + $1", d.giveChange(1600) && Arrays.equals(d.count, drawerOf(200, 2)));

        Drawer tricky = new Drawer(drawerOf(50, 1, 20, 3));
        check("60c from one 50c and three 20c needs the exact search", tricky.giveChange(60) && Arrays.equals(tricky.count, drawerOf(50, 1)));

        Drawer empty = new Drawer(drawerOf(200, 5));
        check("$1 can't come from $2 coins", !empty.giveChange(100) && Arrays.equals(empty.count, drawerOf(200, 5)));
        check("odd cents are impossible", !new Drawer(drawerOf(5, 10)).giveChange(3));
        check("zero change always works", new Drawer(new int[11]).giveChange(0));

        Drawer exact = new Drawer(new int[11]);
        exact.addExact(1785);
        check("an exact payment of $17.85 arrives as $10 $5 $2 50c 20c 10c 5c",
                Arrays.equals(exact.count, drawerOf(1000, 1, 500, 1, 200, 1, 50, 1, 20, 1, 10, 1, 5, 1)));

        check("short of: $3.50 from $2 coins only names $1", Money.name(new Drawer(drawerOf(200, 1)).shortOf(350)).equals("$1"));
    }

    /** Every amount and every small drawer: the fast checks must agree with trying every combination. */
    static void drawerAgainstBruteForce() {
        SplittableRandom rng = new SplittableRandom(4);
        int[] small = {0, 1, 2, 3, 4, 5}; // 5c .. $2
        boolean allAgree = true;
        boolean fewest = true;
        for (int trial = 0; trial < 3000; trial++) {
            int[] f = new int[Money.DENOMS.length];
            for (int i : small) f[i] = rng.nextInt(4);
            long cents = 5L * (1 + rng.nextInt(120));
            int best = bruteFewest(f, cents, small.length - 1);
            Drawer d = new Drawer(f);
            boolean ok = d.giveChange(cents);
            if (ok != (best < Integer.MAX_VALUE)) allAgree = false;
            if (ok) {
                long taken = 0;
                int pieces = 0;
                for (int i = 0; i < f.length; i++) {
                    taken += (long) (f[i] - d.count[i]) * Money.DENOMS[i];
                    pieces += f[i] - d.count[i];
                    if (d.count[i] < 0) allAgree = false;
                }
                if (taken != cents) allAgree = false;
                int[] exact = new Drawer(f).fewestCoins(cents);
                int exactPieces = Arrays.stream(exact).sum();
                if (exactPieces != best || pieces < best) fewest = false;
            }
        }
        check("change is possible exactly when brute force says so, and takes exactly the right amount (3000 random drawers)", allAgree);
        check("the exact search uses the fewest coins", fewest);
    }

    private static int bruteFewest(int[] f, long cents, int i) {
        if (cents == 0) return 0;
        if (i < 0) return Integer.MAX_VALUE;
        int best = Integer.MAX_VALUE;
        for (int n = 0; n <= f[i] && (long) n * Money.DENOMS[i] <= cents; n++) {
            int rest = bruteFewest(f, cents - (long) n * Money.DENOMS[i], i - 1);
            if (rest != Integer.MAX_VALUE) best = Math.min(best, rest + n);
        }
        return best;
    }

    // ---------- Simulator ----------
    static Stall example() throws Exception {
        return Stall.parse(Files.readString(Path.of("examples/lemonade.stall")));
    }

    static void simulator() throws Exception {
        Stall s = example();
        Simulator sim = new Simulator(s, 40, 1);
        int[] rich = new int[Money.DENOMS.length];
        for (int i = 0; i < 9; i++) rich[i] = 500;
        check("a huge float never leaves anyone stuck", sim.run(rich).stuckPerDay() == 0);
        Simulator.Result none = sim.run(new int[Money.DENOMS.length]);
        check("an empty float leaves many stuck", none.stuckPerDay() > 10);
        check("the same seed gives the same days", Arrays.equals(new Simulator(s, 40, 1).run(rich).shortBy(), sim.run(rich).shortBy())
                && new Simulator(s, 40, 1).run(new int[11]).stuckPerDay() == none.stuckPerDay());

        Stall exactOnly = Stall.parse("item a 3.30 weight 1\npays exact 100\n");
        check("if everyone pays exact, no float is needed", new Simulator(exactOnly, 30, 1).run(new int[11]).stuckPerDay() == 0);
        check("days are cut down for very busy stalls", Simulator.daysFor(1000, 2000) == 30 && Simulator.daysFor(100, 120) == 100);
    }

    // ---------- Planner ----------
    static void planner() throws Exception {
        Stall s = example();
        Simulator sim = new Simulator(s, 60, 3);
        int[] plan = Planner.plan(sim, s.budget);
        double mine = sim.run(plan).stuckPerDay();
        check("the plan stays within the budget", Planner.value(plan) <= s.budget);
        check("the plan only uses coins and notes up to $20", plan[9] == 0 && plan[10] == 0);
        check("the plan beats the typical float", mine < sim.run(Planner.typical(s.budget)).stuckPerDay());
        check("the plan beats an empty float", mine < sim.run(new int[11]).stuckPerDay());

        // 40 random floats that spend the same budget: the plan should beat all of them.
        SplittableRandom rng = new SplittableRandom(9);
        boolean beatsRandom = true;
        for (int t = 0; t < 40; t++) {
            int[] f = new int[11];
            long left = s.budget;
            while (left >= 5) {
                int i = rng.nextInt(Planner.FLOAT_DENOMS);
                if (Money.DENOMS[i] <= left) {
                    f[i]++;
                    left -= Money.DENOMS[i];
                }
            }
            if (sim.run(f).stuckPerDay() < mine) beatsRandom = false;
        }
        check("the plan beats 40 random floats with the same budget", beatsRandom);
        check("a zero budget gives an empty float", Planner.value(Planner.plan(sim, 0)) == 0);
        check("the typical float splits the budget across five kinds", Planner.typical(15000)[3] > 0 && Planner.typical(15000)[7] > 0);
    }

    // ---------- Parsing ----------
    static void rejects(String text, String expected, String secret) {
        try {
            Stall.parse(text);
            check("rejects: " + expected, false);
        } catch (InputException e) {
            boolean ok = e.getMessage().contains(expected) && (secret == null || !e.getMessage().contains(secret));
            if (!ok) System.out.println("   got: " + e.getMessage());
            check("rejects: " + expected, ok);
        }
    }

    static void stallParsing() throws Exception {
        String item = "item a 2.00 weight 1\n";
        rejects("dance party\n" + item, "line 1: unknown keyword", "dance");
        rejects("item <script> 2 weight 1\n", "item name is not valid", "script");
        rejects("item a 0 weight 1\n", "from $0.05 to $1000", null);
        rejects("item a 1e9 weight 1\n", "from $0.05 to $1000", null);
        rejects("item a -2 weight 1\n", "from $0.05 to $1000", null);
        rejects("item a 2 weight 0\n", "weight must be", null);
        rejects("item a 2 weight 99999999999\n", "weight must be", null);
        rejects("item a 2 weight 1\nitem a 3 weight 1\n", "already used", null);
        rejects("item a 2\n", "write an item as", null);
        rejects(item + "budget 99999\n", "budget must be", null);
        rejects(item + "budget 10.03\n", "5c steps", null);
        rejects(item + "customers 0\n", "customers must be", null);
        rejects(item + "customers 2001\n", "customers must be", null);
        rejects(item + "basket 3-1\n", "basket", null);
        rejects(item + "basket 0\n", "basket", null);
        rejects(item + "pays exact 50\npays smallest 40\n", "add up to 100 per cent (they add up to 90)", null);
        rejects(item + "pays 7 100\n", "customers pay exact", null);
        rejects(item + "pays exact 50\npays exact 50\n", "already listed", null);
        rejects(item + "title <b>x</b>\n", "title must be", "<b>");
        rejects(item + "title Café\n", "plain printable ASCII", null);
        rejects(item + "title a\u001b[2Jb\n", "plain printable ASCII", null);
        rejects(item + "title a‮b\n", "plain printable ASCII", null);
        rejects("item a 2 weight 1\u0000\n", "plain printable ASCII", null);
        rejects("# nothing\n", "no items", null);
        rejects(item + "x".repeat(300), "longer than 200", null);
        StringBuilder many = new StringBuilder();
        for (int i = 0; i < 31; i++) many.append("item i").append(i).append(" 1 weight 1\n");
        rejects(many.toString(), "too many items", null);

        Stall ok = Stall.parse("title  A stall\r\nbudget 50 # comment\r\nitem a 2.5 weight 3\r\nbasket 2\r\n");
        check("CRLF, comments and defaults are accepted", ok.title.equals("A stall") && ok.budget == 5000 && ok.basketMin == 2
                && ok.items.get(0).cents() == 250 && ok.payments.stream().mapToInt(Stall.Payment::percent).sum() == 100);
    }

    // ---------- Nudges ----------
    static void nudges() throws Exception {
        check("candidates for $4.50 are $4 and $5", Main.candidates(450).equals(List.of(400L, 500L)));
        check("candidates for $2.50 are $2 and $3", Main.candidates(250).equals(List.of(200L, 300L)));
        check("a round $10 needs no nudge", Main.candidates(1000).isEmpty());
        check("$19 can move to $20", Main.candidates(1900).contains(2000L));
    }

    // ---------- Command line ----------
    static int[] runMain(String[] args, byte[] stdin, StringBuilder outText, StringBuilder errText) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        int code = Main.run(args, new ByteArrayInputStream(stdin), new PrintStream(out, true, StandardCharsets.UTF_8),
                new PrintStream(err, true, StandardCharsets.UTF_8));
        outText.append(out.toString(StandardCharsets.UTF_8));
        errText.append(err.toString(StandardCharsets.UTF_8));
        return new int[] {code};
    }

    static void commandLine() throws IOException {
        StringBuilder out = new StringBuilder();
        StringBuilder err = new StringBuilder();
        int code = runMain(new String[] {"--days", "50", "examples/lemonade.stall"}, new byte[0], out, err)[0];
        check("the example runs and reports", code == 1 && out.toString().contains("RECOMMENDED FLOAT") && err.length() == 0);
        check("the example suggests rounding lemonade to $5", out.toString().contains("lemonade       $4.00 -> $5.00"));

        Path tmp = Files.createTempDirectory("changeling");
        try {
            Path easy = tmp.resolve("easy.stall");
            Files.writeString(easy, "budget 100\nitem tea 5 weight 1\npays smallest 100\n");
            out.setLength(0);
            err.setLength(0);
            check("a stall with round prices exits 0", runMain(new String[] {"--days", "50", easy.toString()}, new byte[0], out, err)[0] == 0);

            out.setLength(0);
            err.setLength(0);
            byte[] stdin = Files.readAllBytes(easy);
            check("reads standard input", runMain(new String[] {"--days", "50", "-"}, stdin, out, err)[0] == 0 && out.toString().contains("CHANGELING"));

            Path big = tmp.resolve("big.stall");
            Files.write(big, new byte[70_000]);
            Path binary = tmp.resolve("binary.stall");
            Files.write(binary, new byte[] {(byte) 0xff, (byte) 0xfe, 'a'});
            String[][] bad = {
                {}, {"a", "b"}, {"--days"}, {"--days", "49"}, {"--days", "1e3"}, {"--seed", "-1"}, {"--bogus"},
                {"/no/such/file"}, {"/"}, {big.toString()}, {binary.toString()}, {"/dev/zero"}, {"\u001b]0;owned\u0007$(reboot)"},
            };
            boolean allClean = true;
            for (String[] args : bad) {
                out.setLength(0);
                err.setLength(0);
                int c = runMain(args, new byte[0], out, err)[0];
                String e = err.toString();
                if (c != 2 || out.length() != 0 || !e.startsWith("changeling: ") || e.contains("owned") || e.contains("reboot")) {
                    allClean = false;
                    System.out.println("   bad case " + Arrays.toString(args) + " -> " + c + " " + e);
                }
            }
            check("bad arguments and files give exit 2 and one clean error that never echoes them", allClean);
        } finally {
            try (var files = Files.list(tmp)) {
                for (Path p : (Iterable<Path>) files::iterator) Files.delete(p);
            }
            Files.delete(tmp);
        }
    }
}
