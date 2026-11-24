package spoonfit;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * The fewest scoops from a measuring kit that come within a tolerance of a target volume.
 *
 * <p>An unbounded "coin change" over volumes on a 0.01 ml grid: best[v] is the fewest scoops that
 * add up to exactly v. Every reachable total within the tolerance is a candidate; the answer has
 * the fewest scoops, then the smallest error. Optionally one scoop can be taken back out ("1 cup,
 * less 1 tbsp"), which counts as a scoop too.
 */
public final class Planner {
    public static final int GRID = 100; // steps per ml
    public static final double MAX_ML = 2000;

    public record Scoop(Measures.Measure measure, int count) {}

    public record Plan(List<Scoop> add, Measures.Measure takeOut, double ml, double target) {
        public int scoops() {
            return add.stream().mapToInt(Scoop::count).sum() + (takeOut == null ? 0 : 1);
        }

        public double error() {
            return (ml - target) / target;
        }
    }

    private final List<Measures.Measure> kit;
    private final int[] size;
    private final int[] best; // fewest scoops summing exactly to each grid volume, or MAX for unreachable
    private final int[] via;  // the measure index added last
    private static final int UNREACHABLE = Integer.MAX_VALUE;

    public Planner(List<Measures.Measure> kit) {
        this.kit = List.copyOf(kit);
        int limit = (int) Math.round(MAX_ML * GRID) + 1;
        size = new int[kit.size()];
        for (int i = 0; i < kit.size(); i++) size[i] = (int) Math.round(kit.get(i).ml() * GRID);
        best = new int[limit];
        via = new int[limit];
        Arrays.fill(best, UNREACHABLE);
        best[0] = 0;
        for (int v = 1; v < limit; v++) {
            for (int i = 0; i < size.length; i++) {
                int prev = v - size[i];
                if (prev >= 0 && best[prev] != UNREACHABLE && best[prev] + 1 < best[v]) {
                    best[v] = best[prev] + 1;
                    via[v] = i;
                }
            }
        }
    }

    private List<Scoop> unwind(int v) {
        int[] counts = new int[size.length];
        while (v > 0) {
            counts[via[v]]++;
            v -= size[via[v]];
        }
        List<Scoop> out = new ArrayList<>();
        for (int i = 0; i < counts.length; i++) if (counts[i] > 0) out.add(new Scoop(kit.get(i), counts[i]));
        return out;
    }

    /** The best plan within `tolerance` (a fraction, e.g. 0.03), or the closest one if none is. */
    public Plan plan(double targetMl, double tolerance, boolean allowTakeOut) {
        if (!(targetMl > 0) || targetMl > MAX_ML) throw new Measures.BadInput("amounts must be between 0 and 2 litres");
        if (!(tolerance >= 0) || tolerance > 0.5) throw new Measures.BadInput("tolerance must be 0 to 50%");
        int lo = (int) Math.ceil(targetMl * (1 - tolerance) * GRID - 1e-6);
        int hi = Math.min(best.length - 1, (int) Math.floor(targetMl * (1 + tolerance) * GRID + 1e-6));
        int t = (int) Math.round(targetMl * GRID);
        Plan found = null;
        for (int v = Math.max(1, lo); v <= hi; v++) {
            if (best[v] != UNREACHABLE) found = better(found, new Plan(unwind(v), null, v / (double) GRID, targetMl));
            if (allowTakeOut) {
                for (int i = 0; i < size.length; i++) {
                    int a = v + size[i];
                    if (a < best.length && best[a] != UNREACHABLE && best[a] + 1 < (found == null ? Integer.MAX_VALUE : found.scoops() + 1)) {
                        found = better(found, new Plan(unwind(a), kit.get(i), v / (double) GRID, targetMl));
                    }
                }
            }
        }
        if (found != null) return found;
        // Nothing within tolerance: the closest reachable amount.
        for (int d = 0; d < best.length; d++) {
            for (int v : new int[] {t - d, t + d}) {
                if (v > 0 && v < best.length && best[v] != UNREACHABLE) return new Plan(unwind(v), null, v / (double) GRID, targetMl);
            }
        }
        throw new IllegalStateException("no measure fits");
    }

    private static Plan better(Plan a, Plan b) {
        if (a == null) return b;
        if (b.scoops() != a.scoops()) return b.scoops() < a.scoops() ? b : a;
        if (Math.abs(b.error()) != Math.abs(a.error())) return Math.abs(b.error()) < Math.abs(a.error()) ? b : a;
        return a.takeOut() != null && b.takeOut() == null ? b : a;
    }

    /** Fewest scoops summing exactly to a volume (for tests). */
    int exactScoops(double ml) {
        int v = (int) Math.round(ml * GRID);
        return v < best.length ? best[v] : UNREACHABLE;
    }
}
