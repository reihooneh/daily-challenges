package ferryglide;

import java.util.List;

/**
 * A trip, as read from a plan file. Times are minutes after midnight on the day of the trip;
 * speeds are knots, distances nautical miles, directions degrees true.
 */
public record Plan(
        String trip,
        double paddle,
        int windowStart,
        int windowEnd,
        int step,
        double maxOpposing,
        double maxCross,
        Station station,
        List<Leg> legs) {

    /** The reference current station: when the stream turns and how hard it runs. */
    public record Station(String name, double floodSet, List<Event> events) {}

    /**
     * One line of a current table. speed is signed: positive for maximum flood, negative for
     * maximum ebb, zero for slack water.
     */
    public record Event(int time, double speed) {
        public boolean slack() {
            return speed == 0;
        }
    }

    /**
     * One leg of the route. Like a secondary station in published current tables, each leg's
     * stream follows the reference station's, shifted by {@code offset} minutes and scaled by
     * {@code ratio}. floodSet is the direction the flood runs on this leg.
     */
    public record Leg(String name, double distance, double course, int offset, double ratio, double floodSet) {}
}
