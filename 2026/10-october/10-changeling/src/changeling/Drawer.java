package changeling;

import java.util.Arrays;

/** The cash drawer: how many of each coin and note it holds, and how to give change from it. */
public final class Drawer {
    final int[] count = new int[Money.DENOMS.length];
    private final int[] take = new int[Money.DENOMS.length]; // scratch space, reused

    public Drawer(int[] start) {
        System.arraycopy(start, 0, count, 0, count.length);
    }

    public void add(int denomIndex, int n) {
        count[denomIndex] += n;
    }

    /** Add the coins a customer hands over to pay an exact amount (they use the fewest coins). */
    public void addExact(long cents) {
        for (int i = Money.DENOMS.length - 1; i >= 0 && cents > 0; i--) {
            long n = cents / Money.DENOMS[i];
            count[i] += (int) n;
            cents -= n * Money.DENOMS[i];
        }
    }

    /**
     * Take {@code cents} of change out of the drawer. Returns false, leaving the drawer
     * untouched, if no combination of what is in it adds up to exactly that amount.
     */
    public boolean giveChange(long cents) {
        if (cents == 0) return true;
        if (cents % 5 != 0 || cents < 0) return false;
        // The usual way: biggest coin or note first. It is right almost every time.
        long left = cents;
        for (int i = count.length - 1; i >= 0; i--) {
            int n = (int) Math.min(count[i], left / Money.DENOMS[i]);
            take[i] = n;
            left -= (long) n * Money.DENOMS[i];
        }
        if (left == 0) {
            for (int i = 0; i < count.length; i++) count[i] -= take[i];
            return true;
        }
        // Quick no: if everything small enough to use doesn't add up to the change, give up now.
        long usable = 0;
        for (int i = 0; i < count.length && Money.DENOMS[i] <= cents; i++) usable += (long) count[i] * Money.DENOMS[i];
        if (usable < cents) return false;
        if (!reachable(cents)) return false;
        // Biggest-first can fail with a limited drawer: 60c from one 50c and three 20c
        // needs 20+20+20, not 50+?. Then search properly.
        int[] exact = fewestCoins(cents);
        if (exact == null) return false;
        for (int i = 0; i < count.length; i++) count[i] -= exact[i];
        return true;
    }

    /** The coin or note that ran out: the largest one the change still needed after the drawer's supply was used. */
    public int shortOf(long cents) {
        long left = cents;
        for (int i = count.length - 1; i >= 0; i--) {
            long want = left / Money.DENOMS[i];
            long n = Math.min(count[i], want);
            left -= n * Money.DENOMS[i];
        }
        for (int i = count.length - 1; i >= 0; i--) if (Money.DENOMS[i] <= left) return i;
        return 0;
    }

    /**
     * Exact search: the combination of coins in the drawer that makes {@code cents} with the
     * fewest pieces, or null if none exists. A bounded knapsack in units of 5 cents, with
     * each denomination's supply split into 1, 2, 4, 8... bundles so it becomes 0/1 choices.
     */
    int[] fewestCoins(long cents) {
        int target = (int) (cents / 5);
        int[] bundleDenom = new int[count.length * 32];
        int[] bundleSize = new int[count.length * 32];
        int bundles = 0;
        for (int i = 0; i < count.length; i++) {
            int unit = Money.DENOMS[i] / 5;
            if (unit > target) continue;
            int have = Math.min(count[i], target / unit);
            for (int k = 1; have > 0; k <<= 1) {
                int size = Math.min(k, have);
                bundleDenom[bundles] = i;
                bundleSize[bundles++] = size;
                have -= size;
            }
        }
        final int inf = Integer.MAX_VALUE / 2;
        int[] best = new int[target + 1];
        Arrays.fill(best, inf);
        best[0] = 0;
        long[][] took = new long[bundles][(target >> 6) + 1];
        for (int b = 0; b < bundles; b++) {
            int value = Money.DENOMS[bundleDenom[b]] / 5 * bundleSize[b];
            for (int a = target; a >= value; a--) {
                int through = best[a - value] + bundleSize[b];
                if (best[a - value] < inf && through < best[a]) {
                    best[a] = through;
                    took[b][a >> 6] |= 1L << (a & 63);
                }
            }
        }
        if (best[target] >= inf) return null;
        int[] use = new int[count.length];
        int a = target;
        for (int b = bundles - 1; b >= 0 && a > 0; b--) {
            if ((took[b][a >> 6] >>> (a & 63) & 1L) != 0) {
                use[bundleDenom[b]] += bundleSize[b];
                a -= Money.DENOMS[bundleDenom[b]] / 5 * bundleSize[b];
            }
        }
        return use;
    }

    /**
     * Can the drawer make exactly this amount at all? A fast yes/no answer using a bit set:
     * bit k is set when k x 5 cents can be made. Adding a coin shifts the set left by its
     * value and ORs it in, 64 amounts at a time. Only if the answer is yes do we run the
     * slower search that finds the fewest coins.
     */
    boolean reachable(long cents) {
        int target = (int) (cents / 5);
        int words = (target >> 6) + 1;
        long[] can = new long[words];
        can[0] = 1L;
        for (int i = 0; i < count.length; i++) {
            int unit = Money.DENOMS[i] / 5;
            if (unit > target) continue;
            int have = Math.min(count[i], target / unit);
            for (int k = 1; have > 0; k <<= 1) {
                int size = Math.min(k, have);
                shiftOr(can, unit * size);
                have -= size;
            }
        }
        return (can[target >> 6] >>> (target & 63) & 1L) != 0;
    }

    private static void shiftOr(long[] bits, int shift) {
        int wordShift = shift >> 6;
        int bitShift = shift & 63;
        for (int w = bits.length - 1; w >= wordShift; w--) {
            long v = bits[w - wordShift] << bitShift;
            if (bitShift != 0 && w - wordShift - 1 >= 0) v |= bits[w - wordShift - 1] >>> (64 - bitShift);
            bits[w] |= v;
        }
    }
}
