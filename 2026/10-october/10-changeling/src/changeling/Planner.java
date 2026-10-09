package changeling;

/**
 * Chooses the float: which coins and notes to start the day with, within a budget.
 *
 *   1. Greedy: keep adding the coins or notes (1, 5 or 20 at a time) that remove the most
 *      stuck customers per dollar spent, until nothing helps or the budget is used up.
 *   2. Exchanges: try handing back some of one coin or note and spending that money on
 *      another; keep the exchange that helps most, and repeat.
 *
 * The report then shows how the coins split into bank rolls (40 x 5c, 40 x 10c, 20 x 20c,
 * 20 x 50c, 20 x $1, 25 x $2), since that is how you get them from the bank.
 */
public final class Planner {
    /** The coins and notes worth holding in a float: 5c up to $20. */
    static final int FLOAT_DENOMS = 9;
    static final int MAX_SWAP_ROUNDS = 8;
    static final int MAX_GREEDY_STEPS = 300;
    private static final double EPS = 1e-9;

    private Planner() {}

    public static int chunk(int denomIndex) {
        return Money.ROLL[denomIndex] > 0 ? Money.ROLL[denomIndex] : 1;
    }

    public static long chunkValue(int denomIndex) {
        return (long) chunk(denomIndex) * Money.DENOMS[denomIndex];
    }

    public static long value(int[] f) {
        long v = 0;
        for (int i = 0; i < f.length; i++) v += (long) f[i] * Money.DENOMS[i];
        return v;
    }

    /** Steps the search can take: one coin or note, a handful, or a bank roll's worth. */
    static final int[] STEPS = {1, 5, 20};
    static final int[] GIVE_BACK = {1, 5};

    public static int[] plan(Simulator sim, long budget) {
        return plan(sim, budget, true);
    }

    /** @param exchanges false for a quicker, greedy-only plan (used to compare price nudges). */
    public static int[] plan(Simulator sim, long budget, boolean exchanges) {
        int[] f = new int[Money.DENOMS.length];
        double current = sim.run(f).stuckPerDay();
        // 1. Greedy: the move that removes the most stuck customers per dollar spent.
        for (int steps = 0; steps < MAX_GREEDY_STEPS && current > EPS; steps++) {
            int bestDenom = -1;
            int bestStep = 0;
            double bestRate = 0;
            double bestStuck = current;
            long room = budget - value(f);
            for (int i = 0; i < FLOAT_DENOMS; i++) {
                for (int step : STEPS) {
                    long cost = (long) step * Money.DENOMS[i];
                    if (cost > room) continue;
                    f[i] += step;
                    double s = sim.run(f).stuckPerDay();
                    f[i] -= step;
                    double rate = (current - s) / cost;
                    if (rate > bestRate + EPS) {
                        bestDenom = i;
                        bestStep = step;
                        bestRate = rate;
                        bestStuck = s;
                    }
                }
            }
            if (bestDenom < 0) break;
            f[bestDenom] += bestStep;
            current = bestStuck;
        }
        // 2. Exchanges: hand back some of one coin or note, spend the money on another.
        for (int round = 0; exchanges && round < MAX_SWAP_ROUNDS && current > EPS; round++) {
            int[] best = null;
            double bestStuck = current;
            for (int a = 0; a < FLOAT_DENOMS; a++) {
                for (int giveBack : GIVE_BACK) {
                    if (f[a] < giveBack) continue;
                    for (int b = 0; b < FLOAT_DENOMS; b++) {
                        if (b == a) continue;
                        long room = budget - value(f) + (long) giveBack * Money.DENOMS[a];
                        int take = (int) Math.min(room / Money.DENOMS[b], (long) giveBack * Money.DENOMS[a] / Money.DENOMS[b] + 1);
                        if (take < 1) continue;
                        f[a] -= giveBack;
                        f[b] += take;
                        double s = sim.run(f).stuckPerDay();
                        if (s < bestStuck - EPS) {
                            bestStuck = s;
                            best = f.clone();
                        }
                        f[a] += giveBack;
                        f[b] -= take;
                    }
                }
            }
            if (best == null) break;
            System.arraycopy(best, 0, f, 0, f.length);
            current = bestStuck;
        }
        return f;
    }

    /**
     * The float many stallholders take without planning: the budget split evenly across
     * 50c, $1 and $2 coins and $5 and $10 notes, used only for comparison.
     */
    public static int[] typical(long budget) {
        int[] f = new int[Money.DENOMS.length];
        int[] kinds = {3, 4, 5, 6, 7};
        long share = budget / kinds.length;
        for (int i : kinds) f[i] = (int) (share / chunkValue(i)) * chunk(i);
        return f;
    }
}
