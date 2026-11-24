package spoonfit;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Random;

/** A small test runner (no JUnit: nothing to download). Run with `make test`. */
public final class Tests {
    private Tests() {}

    private static int failures = 0, checks = 0;

    private static void check(boolean ok, String what) {
        checks++;
        if (!ok) {
            failures++;
            System.out.println("FAIL: " + what);
        }
    }

    private static void throwsBad(Runnable r, String what) {
        try {
            r.run();
            check(false, what + " should be refused");
        } catch (Measures.BadInput e) {
            check(true, what);
        }
    }

    static void parsing() {
        Measures.Region au = Measures.Region.AU, us = Measures.Region.US;
        check(Math.abs(Measures.parseLine("2 1/4 cups flour", au).ml() - 562.5) < 1e-9, "mixed number of cups");
        check(Math.abs(Measures.parseLine("1 tbsp oil", au).ml() - 20) < 1e-9, "an Australian tablespoon is 20 ml");
        check(Math.abs(Measures.parseLine("1 tbsp oil", us).ml() - 14.7868) < 1e-9, "a US tablespoon is about 14.8 ml");
        check(Measures.parseLine("1/2 tsp salt", au).ingredient().equals("salt"), "ingredient name");
        check(Double.isNaN(Measures.parseLine("2 large eggs", au).ml()), "eggs aren't a volume");
        check(Double.isNaN(Measures.parseLine("a pinch of salt", au).ml()), "a pinch isn't measured");
        throwsBad(() -> Measures.parseLine("3/0 cup sugar", au), "a zero denominator");
        throwsBad(() -> Measures.parseLine("5/4 cup sugar", au), "an improper fraction");
        throwsBad(() -> Measures.parseLine("9999 l water", au), "an absurd amount");
        throwsBad(() -> Measures.parseLine("1 cup \u001b[31mred", au), "terminal escapes");
        throwsBad(() -> Measures.parseLine("1 cup " + "x".repeat(300), au), "an overlong line");
        throwsBad(() -> Measures.parseKit("1 cup, a spoon", au), "a measure that isn't one");
        throwsBad(() -> Measures.parseKit("0.1 ml", au), "a tiny measure");
        throwsBad(() -> Measures.Region.parse("mars"), "an unknown region");
        throwsBad(() -> Main.options(new String[] {"r.txt", "--scale", "NaN"}), "a NaN scale");
        throwsBad(() -> Main.options(new String[] {"r.txt", "--scale", "1e9"}), "a huge scale");
    }

    /** Fewest scoops to an exact total, by trying every combination of counts. */
    static int brute(int[] sizes, int target, int maxEach) {
        int best = Integer.MAX_VALUE;
        int n = sizes.length;
        int[] c = new int[n];
        while (true) {
            int sum = 0, count = 0;
            for (int i = 0; i < n; i++) {
                sum += c[i] * sizes[i];
                count += c[i];
            }
            if (sum == target) best = Math.min(best, count);
            int i = 0;
            while (i < n && c[i] == maxEach) c[i++] = 0;
            if (i == n) return best;
            c[i]++;
        }
    }

    static void exactness() {
        Random r = new Random(3);
        for (int trial = 0; trial < 40; trial++) {
            int n = 2 + r.nextInt(3);
            List<Measures.Measure> kit = new java.util.ArrayList<>();
            int[] sizes = new int[n];
            for (int i = 0; i < n; i++) {
                sizes[i] = 1 + r.nextInt(40);
                kit.add(new Measures.Measure("m" + i, sizes[i]));
            }
            Planner p = new Planner(kit);
            for (int t = 1; t <= 60; t++) {
                int want = bruteMl(sizes, t);
                int got = p.exactScoops(t);
                check(want == got, "exact scoops for " + t + " ml, trial " + trial);
            }
        }
    }

    static int bruteMl(int[] sizesMl, int target) {
        return brute(sizesMl, target, 60);
    }

    static void plans() {
        List<Measures.Measure> kit = Measures.standardKit(Measures.Region.AU);
        Planner p = new Planner(kit);
        Planner.Plan cup = p.plan(250, 0.0, false);
        check(cup.scoops() == 1 && cup.add().get(0).measure().ml() == 250, "one cup is one scoop");
        Planner.Plan vanilla = p.plan(14.7868, 0.05, true);
        check(vanilla.scoops() == 2 && vanilla.takeOut() != null, "a US tablespoon in an AU kit: 1 tbsp less 1 tsp");
        Planner.Plan noTake = p.plan(14.7868, 0.05, false);
        check(noTake.scoops() == 3 && noTake.takeOut() == null, "without taking out: 3 tsp");
        for (double t = 1; t < 600; t += 7.3) {
            Planner.Plan a = p.plan(t, 0.05, true);
            double sum = a.add().stream().mapToDouble(s -> s.count() * s.measure().ml()).sum() - (a.takeOut() == null ? 0 : a.takeOut().ml());
            check(Math.abs(sum - a.ml()) < 0.05, "the plan adds up at " + t);
            Planner.Plan b = p.plan(t, 0.05, false);
            check(a.scoops() <= b.scoops() || Math.abs(b.error()) > 0.05, "taking out never costs scoops at " + t);
        }
        throwsBad(() -> p.plan(-1, 0.05, true), "a negative amount");
        throwsBad(() -> p.plan(Double.NaN, 0.05, true), "a NaN amount");
    }

    static void endToEnd() throws IOException {
        String out = Main.run(Main.options(new String[] {"examples/brownies.txt", "--scale", "1.5"}), Files.readString(Path.of("examples/brownies.txt")));
        check(out.contains("1 tbsp, less 1 tsp"), "vanilla in the example");
        check(out.contains("not a volume"), "eggs passed through");
        check(out.contains("closest your kit can do"), "the 1/4 tsp warning");
        Path dir = Files.createTempDirectory("spoonfit");
        throwsBad(() -> {
            try {
                Main.read(dir);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        }, "a directory as the recipe");
        Path bin = dir.resolve("bin.txt");
        Files.write(bin, new byte[] {(byte) 0xff, (byte) 0xfe, 0x41});
        throwsBad(() -> {
            try {
                Main.read(bin);
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
        }, "a file that isn't UTF-8");
        String many = "1 cup water\n".repeat(300);
        throwsBad(() -> Main.run(Main.options(new String[] {"x"}), many), "too many lines");
    }

    public static void main(String[] args) throws IOException {
        parsing();
        exactness();
        plans();
        endToEnd();
        System.out.println(failures == 0 ? "All " + checks + " Spoonfit checks passed." : failures + " of " + checks + " checks failed.");
        if (failures > 0) System.exit(1);
    }
}
