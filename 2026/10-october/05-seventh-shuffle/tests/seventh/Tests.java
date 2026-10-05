package seventh;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;

/** A tiny test runner, so the project needs nothing beyond the JDK. */
public final class Tests {
    private static int passed;
    private static int failed;

    private interface Check {
        void run() throws Exception;
    }

    private static void test(String name, Check check) {
        try {
            check.run();
            passed++;
        } catch (Throwable problem) {
            failed++;
            System.out.println("FAIL  " + name + "\n      " + problem);
        }
    }

    private static void equal(Object expected, Object actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError("expected " + expected + " but got " + actual);
        }
    }

    private static void yes(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void rejected(String deckText, String expectedPart) {
        try {
            Deck.parse(deckText);
        } catch (InputException e) {
            yes(e.getMessage().contains(expectedPart), "wrong message: " + e.getMessage());
            return;
        }
        throw new AssertionError("should have been rejected");
    }

    private static String[] cli(String stdin, String... args) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        int code = Main.run(args, new ByteArrayInputStream(stdin.getBytes(StandardCharsets.UTF_8)),
                new PrintStream(out, true, StandardCharsets.UTF_8), new PrintStream(err, true, StandardCharsets.UTF_8));
        return new String[] {String.valueOf(code), out.toString(StandardCharsets.UTF_8), err.toString(StandardCharsets.UTF_8)};
    }

    private static String rounded(BigDecimal value) {
        return value.setScale(3, RoundingMode.HALF_UP).toPlainString();
    }

    public static void main(String[] args) {
        // ---- rising sequences ------------------------------------------------
        test("a new deck has one rising sequence", () -> equal(1, Riffle.risingSequences(Shuffler.newDeck(52))));
        test("a reversed deck has n rising sequences", () -> equal(5, Riffle.risingSequences(new int[] {4, 3, 2, 1, 0})));
        test("rising sequences of a hand-worked example", () -> {
            // 1 2 | 3 4 5 riffled together: 3 1 4 2 5  ->  sequences {1,2} and {3,4,5}
            equal(2, Riffle.risingSequences(Deck.parse("3 1 4 2 5")));
        });
        test("fewest shuffles is the base-2 logarithm, rounded up", () -> {
            equal(0, Riffle.minimumShuffles(1));
            equal(1, Riffle.minimumShuffles(2));
            equal(2, Riffle.minimumShuffles(3));
            equal(5, Riffle.minimumShuffles(27));
            equal(6, Riffle.minimumShuffles(33));
        });

        // ---- exact mathematics ----------------------------------------------
        test("published distances for 52 cards (Bayer and Diaconis)", () -> {
            String[] published = {"1.000", "1.000", "1.000", "1.000", "0.924", "0.614", "0.334", "0.167", "0.085", "0.043"};
            for (int k = 1; k <= 10; k++) {
                equal(published[k - 1], rounded(Riffle.distanceFromRandom(52, k)));
            }
        });
        test("distance never increases with more shuffles", () -> {
            for (int n : new int[] {2, 3, 10, 52, 104}) {
                BigDecimal previous = BigDecimal.ONE;
                for (int k = 0; k <= 15; k++) {
                    BigDecimal distance = Riffle.distanceFromRandom(n, k);
                    yes(distance.compareTo(previous) <= 0 && distance.signum() >= 0, "n=" + n + " k=" + k);
                    previous = distance;
                }
            }
        });
        test("probabilities of all orders add up to exactly 1", () -> {
            for (int n : new int[] {2, 5, 13, 52}) {
                BigInteger[] eulerian = Riffle.eulerian(n);
                for (int k = 0; k <= 8; k++) {
                    BigInteger total = BigInteger.ZERO;
                    for (int r = 1; r <= n; r++) {
                        total = total.add(eulerian[r - 1].multiply(Riffle.orderings(n, r, k)));
                    }
                    equal(BigInteger.ONE.shiftLeft(k * n), total);
                }
            }
        });
        test("Eulerian numbers match the known row for 5 and sum to n!", () -> {
            equal("[1, 26, 66, 26, 1]", java.util.Arrays.toString(Riffle.eulerian(5)));
            BigInteger sum = BigInteger.ZERO;
            for (BigInteger value : Riffle.eulerian(52)) {
                sum = sum.add(value);
            }
            equal(Riffle.factorial(52), sum);
        });
        test("binomial coefficients", () -> {
            equal(BigInteger.valueOf(2_598_960), Riffle.binomial(BigInteger.valueOf(52), 5));
            equal(BigInteger.ONE, Riffle.binomial(BigInteger.valueOf(7), 7));
            equal(BigInteger.ZERO, Riffle.binomial(BigInteger.valueOf(6), 7));
        });
        test("an impossible order has likelihood zero", () -> {
            // 5 rising sequences cannot appear after 2 shuffles (at most 4).
            equal(0, Riffle.likelihoodRatio(52, 5, 2).signum());
            yes(Riffle.likelihoodRatio(52, 4, 2).signum() > 0, "4 sequences are possible after 2 shuffles");
        });
        test("after many shuffles every order approaches chance", () -> {
            for (int r : new int[] {1, 20, 27, 52}) {
                BigDecimal ratio = Riffle.likelihoodRatio(52, r, 20);
                yes(ratio.subtract(BigDecimal.ONE).abs().compareTo(new BigDecimal("0.01")) < 0, "r=" + r);
            }
        });

        // ---- the simulator ---------------------------------------------------
        test("a shuffle keeps every card exactly once and leaves its input alone", () -> {
            Random random = new Random(3);
            int[] start = Shuffler.newDeck(52);
            int[] after = Shuffler.riffle(start, 9, random);
            equal(1, Riffle.risingSequences(start));
            int[] sorted = after.clone();
            java.util.Arrays.sort(sorted);
            yes(java.util.Arrays.equals(sorted, start), "cards were lost or duplicated");
        });
        test("k shuffles never produce more than 2^k rising sequences", () -> {
            Random random = new Random(11);
            for (int trial = 0; trial < 2000; trial++) {
                int k = 1 + trial % 5;
                int r = Riffle.risingSequences(Shuffler.riffle(Shuffler.newDeck(52), k, random));
                yes(r <= (1 << k), "k=" + k + " r=" + r);
            }
        });
        test("simulated shuffles match the formula (4 cards, 2 shuffles)", () -> {
            Random random = new Random(2026);
            int trials = 200_000;
            Map<String, Integer> counts = new HashMap<>();
            for (int i = 0; i < trials; i++) {
                counts.merge(Deck.format(Shuffler.riffle(Shuffler.newDeck(4), 2, random), false), 1, Integer::sum);
            }
            for (Map.Entry<String, Integer> entry : counts.entrySet()) {
                int r = Riffle.risingSequences(Deck.parse(entry.getKey()));
                double expected = Riffle.orderings(4, r, 2).doubleValue() / 256.0;
                double observed = entry.getValue() / (double) trials;
                yes(Math.abs(observed - expected) < 0.005, entry.getKey() + ": " + observed + " vs " + expected);
            }
        });
        test("the same seed deals the same deck", () -> equal(cli("", "deal", "--seed", "5")[1], cli("", "deal", "--seed", "5")[1]));
        test("without a seed, two deals differ", () -> yes(!cli("", "deal")[1].equals(cli("", "deal")[1]), "identical deals"));

        // ---- verdicts --------------------------------------------------------
        test("few shuffles are caught; many are not", () -> {
            Random random = new Random(52);
            int caughtAtFour = 0;
            int flaggedAtTwelve = 0;
            for (int i = 0; i < 300; i++) {
                if (Verdict.of(Shuffler.riffle(Shuffler.newDeck(52), 4, random)).underShuffled) {
                    caughtAtFour++;
                }
                if (Verdict.of(Shuffler.riffle(Shuffler.newDeck(52), 12, random)).underShuffled) {
                    flaggedAtTwelve++;
                }
            }
            equal(300, caughtAtFour);
            yes(flaggedAtTwelve <= 3, "false alarms after 12 shuffles: " + flaggedAtTwelve);
        });
        test("a three-shuffle deck is dated correctly", () -> {
            Verdict verdict = Verdict.of(Shuffler.riffle(Shuffler.newDeck(52), 3, new Random(1)));
            equal(3, verdict.mostLikelyShuffles);
            yes(verdict.underShuffled, "should be flagged");
        });
        test("huge numbers are printed readably", () -> {
            equal("3.2", Verdict.readable(new BigDecimal("3.17")));
            equal("150", Verdict.readable(new BigDecimal("150.4")));
            equal("45,200", Verdict.readable(new BigDecimal("45200.3")));
            equal("4.1 million", Verdict.readable(new BigDecimal("4100000")));
            equal("about 10^31", Verdict.readable(new BigDecimal("1.5E+31")));
        });

        // ---- parsing ---------------------------------------------------------
        test("card names, tens, symbols, commas and comments", () -> {
            String deck = Deck.format(Shuffler.newDeck(52), true);
            equal(1, Riffle.risingSequences(Deck.parse("# new deck\n" + deck.replace(" ", ", ").toLowerCase())));
            equal(1, Riffle.risingSequences(Deck.parse(deck.replace("10", "T").replace('S', '♠'))));
        });
        test("format and parse are inverses", () -> {
            int[] deck = Shuffler.riffle(Shuffler.newDeck(52), 7, new Random(8));
            yes(java.util.Arrays.equals(deck, Deck.parse(Deck.format(deck, true))), "cards");
            int[] big = Shuffler.riffle(Shuffler.newDeck(520), 7, new Random(8));
            yes(java.util.Arrays.equals(big, Deck.parse(Deck.format(big, false))), "numbers");
        });

        // ---- hostile and broken input ---------------------------------------
        test("rejects decks that are not a complete set", () -> {
            rejected("1 2 2", "duplicate");
            rejected("1 2 4", "not a number between 1 and 3");
            rejected("0 1 2", "not a number between 1 and 3");
            rejected("1", "at least 2 cards");
            rejected("", "at least 2 cards");
            rejected("AS KH", "exactly 52 cards");
            rejected(Deck.format(Shuffler.newDeck(52), true).replace("KC", "AS"), "duplicate");
            rejected(Deck.format(Shuffler.newDeck(52), true).replace("KC", "1X"), "not a card");
        });
        test("rejects hostile text without echoing it", () -> {
            String[] attacks = {"1 2 <script>alert(1)</script>", "1 2 $(rm -rf ~)", "1 2 ../../etc/passwd",
                "1 2 \u001b[2J\u001b]0;owned\u0007", "1 2 -3", "1 2 3.0", "1 2 1e3", "1 2 0x3", "1 2 ٣",
                "1 2 99999999999999999999", "1 2 %s%n", "1 2 3\u0000"};
            for (String attack : attacks) {
                try {
                    Deck.parse(attack);
                    throw new AssertionError("accepted: " + attack);
                } catch (InputException e) {
                    yes(!e.getMessage().contains("script") && !e.getMessage().contains("owned")
                            && !e.getMessage().contains("\u001b") && !e.getMessage().contains("etc"), "echoed input");
                }
            }
        });
        test("rejects oversized input", () -> {
            rejected("1 ".repeat(521), "at most 520 cards");
            rejected("1 ".repeat(20_000), "longer than");
            rejected(null, "no deck");
            equal("2", cli("7 ".repeat(100_000), "check", "-")[0]);
        });
        test("the largest allowed deck is analysed quickly", () -> {
            long started = System.nanoTime();
            Verdict.of(Shuffler.riffle(Shuffler.newDeck(520), 9, new Random(4)));
            Riffle.distanceFromRandom(520, 20);
            yes((System.nanoTime() - started) / 1e9 < 20, "too slow");
        });
        test("command line: exit codes and clean errors", () -> {
            equal("1", cli("1 2 3 4 5 6 7 8", "check", "-")[0]);
            equal("0", cli(Deck.format(Shuffler.riffle(Shuffler.newDeck(52), 12, new Random(6)), true), "check", "-")[0]);
            equal("0", cli("", "--help")[0]);
            equal("2", cli("")[0]);
            for (String[] bad : new String[][] {
                {"check"}, {"check", "/no/such/file"}, {"check", "/"}, {"check", "a\u0000b"}, {"check", "../../../etc/shadow/x"},
                {"deal", "--shuffles", "21"}, {"deal", "--shuffles", "-1"}, {"deal", "--cards", "521"},
                {"deal", "--cards", "1"}, {"deal", "--cards"}, {"deal", "--seed", "abc"}, {"deal", "--cards", "9".repeat(30)},
                {"deal", "--bogus", "1"}, {"table", "--cards", "0"}, {"table", "x"}, {"explode"}}) {
                String[] result = cli("", bad);
                equal("2", result[0]);
                equal("", result[1]);
                yes(result[2].startsWith("seventh: ") && result[2].lines().count() == 1, "untidy error: " + result[2]);
            }
        });
        test("invalid UTF-8 is refused", () -> {
            ByteArrayOutputStream err = new ByteArrayOutputStream();
            int code = Main.run(new String[] {"check", "-"}, new ByteArrayInputStream(new byte[] {'1', ' ', (byte) 0xff, (byte) 0xfe}),
                    new PrintStream(new ByteArrayOutputStream()), new PrintStream(err));
            equal(2, code);
            yes(err.toString().contains("UTF-8"), err.toString());
        });

        System.out.println(passed + " passed, " + failed + " failed");
        System.exit(failed == 0 ? 0 : 1);
    }
}
