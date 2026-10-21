package ferryglide;

import java.util.ArrayList;
import java.util.List;

/** Tries every departure time in the window and finds the good ones. */
public final class Planner {
    /** A run of departure times that all keep within the limits. */
    public record Window(int from, int to, double fastest, double slowest) {}

    public record Result(List<Navigator.Trip> trips, Navigator.Trip best, Navigator.Trip fastestIgnoringLimits,
                         List<Window> windows, double stillWaterMinutes) {}

    private Planner() {}

    public static Result plan(Plan plan) {
        Current current = new Current(plan.station().events());
        Navigator nav = new Navigator(current, plan.paddle());
        List<Navigator.Trip> trips = new ArrayList<>();
        Navigator.Trip best = null, fastest = null;
        for (int d = plan.windowStart(); d <= plan.windowEnd(); d += plan.step()) {
            Navigator.Trip t = nav.run(plan.legs(), d, plan.maxOpposing(), plan.maxCross());
            trips.add(t);
            boolean finished = t.failure() == null || t.legs().stream().allMatch(Navigator.LegRun::ok);
            if (finished && (fastest == null || t.minutes() < fastest.minutes() - 1e-9)) fastest = t;
            if (t.ok() && (best == null || t.minutes() < best.minutes() - 1e-9)) best = t;
        }
        List<Window> windows = new ArrayList<>();
        int i = 0;
        while (i < trips.size()) {
            if (!trips.get(i).ok()) { i++; continue; }
            int j = i;
            double lo = Double.MAX_VALUE, hi = 0;
            while (j < trips.size() && trips.get(j).ok()) {
                lo = Math.min(lo, trips.get(j).minutes());
                hi = Math.max(hi, trips.get(j).minutes());
                j++;
            }
            windows.add(new Window(trips.get(i).departure(), trips.get(j - 1).departure(), lo, hi));
            i = j;
        }
        double still = plan.legs().stream().mapToDouble(Plan.Leg::distance).sum() / plan.paddle() * 60;
        return new Result(trips, best, fastest, windows, still);
    }
}
