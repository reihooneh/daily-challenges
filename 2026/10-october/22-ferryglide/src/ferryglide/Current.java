package ferryglide;

import java.util.List;

/**
 * The tidal stream at the reference station, between the events of its current table.
 *
 * Current tables give only the turning points: slack water and the maximum flood or ebb. In
 * between, navigators use the "rule of cosine" (as in the NOAA tables): from slack the stream
 * builds like a sine wave to its maximum, then dies back the same way to the next slack.
 */
public final class Current {
    private final List<Plan.Event> events;

    public Current(List<Plan.Event> events) {
        this.events = events;
    }

    public int first() {
        return events.get(0).time();
    }

    public int last() {
        return events.get(events.size() - 1).time();
    }

    /** Signed stream in knots (flood positive), or NaN outside the table. t in minutes. */
    public double at(double t) {
        if (!(t >= first() && t <= last())) return Double.NaN;
        for (int i = 0; i + 1 < events.size(); i++) {
            Plan.Event a = events.get(i), b = events.get(i + 1);
            if (t > b.time()) continue;
            double f = (t - a.time()) / (double) (b.time() - a.time());
            if (a.slack()) return b.speed() * Math.sin(Math.PI / 2 * f);   // building from slack
            return a.speed() * Math.cos(Math.PI / 2 * f);                   // easing towards slack
        }
        return 0;
    }

    /** Slack times in the table (minutes), for the report. */
    public int[] slacks() {
        return events.stream().filter(Plan.Event::slack).mapToInt(Plan.Event::time).toArray();
    }
}
