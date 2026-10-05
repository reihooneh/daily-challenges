package seventh;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.MathContext;

/**
 * The mathematics of the riffle shuffle (Bayer and Diaconis, 1992).
 *
 * <p>Everything is computed exactly with big integers, so there is no rounding
 * error until the very last step where a result is turned into a decimal.
 */
public final class Riffle {
    public static final int MAX_SHUFFLES = 20;
    private static final MathContext PRECISION = new MathContext(30);

    private Riffle() {
    }

    /**
     * Counts rising sequences: maximal runs of cards 1, 2, 3, ... that still
     * appear in order (not necessarily next to each other). A new deck has 1.
     * One riffle shuffle can at most double the number.
     */
    public static int risingSequences(int[] order) {
        int n = order.length;
        int[] position = new int[n];
        for (int i = 0; i < n; i++) {
            position[order[i]] = i;
        }
        int sequences = 1;
        for (int card = 1; card < n; card++) {
            if (position[card] < position[card - 1]) {
                sequences++;
            }
        }
        return sequences;
    }

    /** The fewest riffle shuffles that could have produced r rising sequences. */
    public static int minimumShuffles(int risingSequences) {
        int k = 0;
        while ((1L << k) < risingSequences) {
            k++;
        }
        return k;
    }

    /**
     * Numerator of the Bayer-Diaconis formula. After k riffle shuffles, the
     * chance of one particular order with r rising sequences is
     * C(2^k + n - r, n) / 2^(k*n).
     */
    static BigInteger orderings(int n, int r, int k) {
        return binomial(BigInteger.ONE.shiftLeft(k).add(BigInteger.valueOf((long) n - r)), n);
    }

    /**
     * How many times more likely this order is after k shuffles than it would
     * be in a perfectly shuffled deck (where every order has chance 1/n!).
     */
    public static BigDecimal likelihoodRatio(int n, int r, int k) {
        check(n, r, k);
        BigInteger numerator = orderings(n, r, k).multiply(factorial(n));
        BigInteger denominator = BigInteger.ONE.shiftLeft(k * n);
        return new BigDecimal(numerator).divide(new BigDecimal(denominator), PRECISION);
    }

    /** The shuffle count (0..MAX_SHUFFLES) under which this order is most likely. */
    public static int mostLikelyShuffles(int n, int r) {
        int best = 0;
        BigDecimal bestRatio = BigDecimal.valueOf(-1);
        for (int k = 0; k <= MAX_SHUFFLES; k++) {
            BigDecimal ratio = likelihoodRatio(n, r, k);
            if (ratio.compareTo(bestRatio) > 0) {
                best = k;
                bestRatio = ratio;
            }
        }
        return best;
    }

    /**
     * Total variation distance from a perfectly shuffled deck after k riffle
     * shuffles: 0 means perfectly random, 1 means nothing like random.
     *
     * <p>All orders with the same number of rising sequences are equally
     * likely, so instead of summing over n! orders we sum over r = 1..n and
     * weight by the Eulerian number (how many orders have r rising sequences).
     */
    public static BigDecimal distanceFromRandom(int n, int k) {
        check(n, 1, k);
        BigInteger[] eulerian = eulerian(n);
        BigInteger nFactorial = factorial(n);
        BigInteger twoToKn = BigInteger.ONE.shiftLeft(k * n);
        // sum over r of A(n,r) * | C(...)*n! - 2^(kn) |, then divide by 2 * n! * 2^(kn)
        BigInteger sum = BigInteger.ZERO;
        for (int r = 1; r <= n; r++) {
            BigInteger difference = orderings(n, r, k).multiply(nFactorial).subtract(twoToKn).abs();
            sum = sum.add(eulerian[r - 1].multiply(difference));
        }
        BigInteger denominator = nFactorial.multiply(twoToKn).shiftLeft(1);
        return new BigDecimal(sum).divide(new BigDecimal(denominator), PRECISION);
    }

    /** eulerian(n)[d] = number of orders of n cards with d descents (d + 1 rising sequences). */
    static BigInteger[] eulerian(int n) {
        BigInteger[] row = {BigInteger.ONE};
        for (int size = 2; size <= n; size++) {
            BigInteger[] next = new BigInteger[size];
            for (int d = 0; d < size; d++) {
                BigInteger stay = d < size - 1 ? row[d].multiply(BigInteger.valueOf(d + 1L)) : BigInteger.ZERO;
                BigInteger grow = d > 0 ? row[d - 1].multiply(BigInteger.valueOf((long) size - d)) : BigInteger.ZERO;
                next[d] = stay.add(grow);
            }
            row = next;
        }
        return row;
    }

    static BigInteger factorial(int n) {
        BigInteger result = BigInteger.ONE;
        for (int i = 2; i <= n; i++) {
            result = result.multiply(BigInteger.valueOf(i));
        }
        return result;
    }

    /** C(top, choose) for a possibly huge top and a small choose. Zero when top < choose. */
    static BigInteger binomial(BigInteger top, int choose) {
        if (top.compareTo(BigInteger.valueOf(choose)) < 0) {
            return BigInteger.ZERO;
        }
        BigInteger result = BigInteger.ONE;
        for (int i = 1; i <= choose; i++) {
            // Multiply before dividing: the running product of i consecutive
            // numbers is always divisible by i!, so this division is exact.
            result = result.multiply(top.subtract(BigInteger.valueOf((long) choose - i)))
                    .divide(BigInteger.valueOf(i));
        }
        return result;
    }

    private static void check(int n, int r, int k) {
        if (n < 2 || n > Deck.MAX_CARDS) {
            throw new IllegalArgumentException("deck size out of range");
        }
        if (r < 1 || r > n) {
            throw new IllegalArgumentException("rising sequences out of range");
        }
        if (k < 0 || k > MAX_SHUFFLES) {
            throw new IllegalArgumentException("shuffle count out of range");
        }
    }
}
