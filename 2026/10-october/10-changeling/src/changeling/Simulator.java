package changeling;

import java.util.SplittableRandom;

/**
 * Plays out many market days: customers arrive, buy, pay, and need change from the drawer.
 *
 * The customers are generated once, from a fixed seed, and every float is tried against
 * the very same customers ("common random numbers"). So when one float beats another,
 * it is because the float is better, not because it happened to meet luckier customers.
 */
public final class Simulator {
    /** One customer: what they owe after cash rounding, and what they hand over. */
    record Customer(long total, int note, int notes) {
        boolean exact() {
            return note < 0;
        }
    }

    public record Result(double stuckPerDay, double daysWithStuck, double lostPerDay, int[] shortBy, long served) {}

    private static final int[] NOTES = {6, 7, 8, 9, 10}; // indexes of $5, $10, $20, $50, $100

    /** Keeps every simulation small enough to repeat hundreds of times: days x customers. */
    public static final int MAX_CUSTOMERS_PER_RUN = 60_000;

    /** How many days to simulate: what was asked for, cut down for very busy stalls. */
    public static int daysFor(int requested, int customersPerDay) {
        return Math.max(20, Math.min(requested, MAX_CUSTOMERS_PER_RUN / customersPerDay));
    }

    final Customer[][] days;

    public Simulator(Stall stall, int dayCount, long seed) {
        SplittableRandom rng = new SplittableRandom(seed);
        int weightSum = stall.items.stream().mapToInt(Stall.Item::weight).sum();
        days = new Customer[dayCount][stall.customers];
        for (int d = 0; d < dayCount; d++) {
            for (int c = 0; c < stall.customers; c++) {
                int basket = stall.basketMin + rng.nextInt(stall.basketMax - stall.basketMin + 1);
                long sum = 0;
                for (int b = 0; b < basket; b++) sum += pick(stall, weightSum, rng.nextInt(weightSum)).cents();
                long total = Money.roundCash(sum);
                days[d][c] = pay(stall, total, rng.nextInt(100));
            }
        }
    }

    private static Stall.Item pick(Stall stall, int weightSum, int r) {
        for (Stall.Item it : stall.items) {
            r -= it.weight();
            if (r < 0) return it;
        }
        return stall.items.get(stall.items.size() - 1);
    }

    private static Customer pay(Stall stall, long total, int r) {
        Stall.Payment way = stall.payments.get(stall.payments.size() - 1);
        for (Stall.Payment p : stall.payments) {
            r -= p.percent();
            if (r < 0) {
                way = p;
                break;
            }
        }
        if (way.kind() == Stall.PayKind.EXACT) return new Customer(total, -1, 0);
        if (way.kind() == Stall.PayKind.NOTE && Money.DENOMS[way.note()] >= total) return new Customer(total, way.note(), 1);
        for (int i : NOTES) if (Money.DENOMS[i] >= total) return new Customer(total, i, 1);
        int hundred = NOTES[NOTES.length - 1];
        return new Customer(total, hundred, (int) ((total + 9999) / 10000));
    }

    /** Run every simulated day starting from this float. */
    public Result run(int[] start) {
        int stuck = 0;
        int badDays = 0;
        long lost = 0;
        long served = 0;
        int[] shortBy = new int[Money.DENOMS.length];
        for (Customer[] day : days) {
            Drawer drawer = new Drawer(start);
            int stuckToday = 0;
            for (Customer c : day) {
                if (c.exact()) {
                    drawer.addExact(c.total());
                    served++;
                    continue;
                }
                long change = (long) Money.DENOMS[c.note()] * c.notes() - c.total();
                if (drawer.giveChange(change)) {
                    drawer.add(c.note(), c.notes());
                    served++;
                } else {
                    shortBy[drawer.shortOf(change)]++;
                    stuckToday++;
                    lost += c.total();
                }
            }
            stuck += stuckToday;
            if (stuckToday > 0) badDays++;
        }
        int n = days.length;
        return new Result((double) stuck / n, (double) badDays / n, (double) lost / n, shortBy, served);
    }
}
