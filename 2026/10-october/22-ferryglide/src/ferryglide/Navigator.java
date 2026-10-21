package ferryglide;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Paddling a leg through a moving stream: the vector triangle.
 *
 * The stream on a leg is split into a part along the course (helping or hindering) and a part
 * across it. To stay on the line, the paddler points partly into the cross-current: a ferry
 * glide. With paddle speed P and cross-current c, the heading is turned by asin(c / P) and the
 * speed made good along the course is sqrt(P^2 - c^2) + (current along the course). If the
 * cross-current is as fast as the paddler, the line can't be held at all.
 */
public final class Navigator {
    /** Below this speed over the ground a paddler is effectively stuck. */
    public static final double MIN_GROUND = 0.3;
    private static final double DT = 0.5;  // minutes per integration step

    /** The stream on a leg at a moment, resolved against the course. */
    public record Stream(double along, double cross, double speed) {}

    /** How a leg went. */
    public record LegRun(Plan.Leg leg, double start, double end, double maxOpposing, double maxCross,
                         double maxFerryAngle, double headingAtStart, String failure) {
        public boolean ok() {
            return failure == null;
        }

        public double minutes() {
            return end - start;
        }
    }

    /** A whole trip from one departure time. */
    public record Trip(int departure, List<LegRun> legs, boolean ok, String failure, double arrival,
                       double maxOpposing, double maxCross) {
        public double minutes() {
            return arrival - departure;
        }
    }

    private final Current current;
    private final double paddle;

    public Navigator(Current current, double paddle) {
        this.current = current;
        this.paddle = paddle;
    }

    /** The stream on this leg at time t, or null outside the current table. */
    public Stream stream(Plan.Leg leg, double t) {
        double c = current.at(t - leg.offset());
        if (Double.isNaN(c)) return null;
        c *= leg.ratio();
        double set = c >= 0 ? leg.floodSet() : leg.floodSet() + 180;
        double s = Math.abs(c);
        double rel = Math.toRadians(set - leg.course());
        return new Stream(s * Math.cos(rel), s * Math.sin(rel), s);
    }

    /** Speed made good along the course with this stream, or NaN if the course can't be held. */
    public double groundSpeed(Stream s) {
        if (Math.abs(s.cross()) >= paddle) return Double.NaN;
        return Math.sqrt(paddle * paddle - s.cross() * s.cross()) + s.along();
    }

    /** Heading to steer (degrees true) to stay on the course in this stream. */
    public double heading(Plan.Leg leg, Stream s) {
        double ferry = Math.toDegrees(Math.asin(Math.max(-1, Math.min(1, s.cross() / paddle))));
        return norm(leg.course() - ferry);
    }

    public LegRun runLeg(Plan.Leg leg, double start) {
        double t = start, covered = 0, maxOpp = 0, maxCross = 0, maxFerry = 0;
        Stream first = stream(leg, start);
        double headingStart = first == null ? leg.course() : heading(leg, first);
        while (covered < leg.distance()) {
            if (t - start > 24 * 60) return new LegRun(leg, start, t, maxOpp, maxCross, maxFerry, headingStart, "never arrives");
            Stream s = stream(leg, t + DT / 2);
            if (s == null) return new LegRun(leg, start, t, maxOpp, maxCross, maxFerry, headingStart, "runs past the end of the current table");
            maxOpp = Math.max(maxOpp, -s.along());
            maxCross = Math.max(maxCross, Math.abs(s.cross()));
            double gs = groundSpeed(s);
            if (Double.isNaN(gs)) return new LegRun(leg, start, t, maxOpp, maxCross, maxFerry, headingStart, "the cross-current is faster than you paddle");
            maxFerry = Math.max(maxFerry, Math.toDegrees(Math.asin(Math.abs(s.cross()) / paddle)));
            if (gs < MIN_GROUND) return new LegRun(leg, start, t, maxOpp, maxCross, maxFerry, headingStart, "the current stops you");
            double step = gs * DT / 60;  // nautical miles this step
            if (covered + step >= leg.distance()) {
                t += DT * (leg.distance() - covered) / step;
                covered = leg.distance();
            } else {
                covered += step;
                t += DT;
            }
        }
        return new LegRun(leg, start, t, maxOpp, maxCross, maxFerry, headingStart, null);
    }

    /** Paddles every leg in turn from the departure time, stopping at the first failure. */
    public Trip run(List<Plan.Leg> legs, int departure, double limitOpposing, double limitCross) {
        List<LegRun> runs = new ArrayList<>();
        double t = departure, opp = 0, cross = 0;
        for (Plan.Leg leg : legs) {
            LegRun r = runLeg(leg, t);
            runs.add(r);
            opp = Math.max(opp, r.maxOpposing());
            cross = Math.max(cross, r.maxCross());
            if (!r.ok()) return new Trip(departure, runs, false, leg.name() + ": " + r.failure(), r.end(), opp, cross);
            t = r.end();
        }
        String why = null;
        if (opp > limitOpposing + 1e-9) why = String.format(Locale.ROOT, "%.1f kn against you (your limit is %.1f)", opp, limitOpposing);
        else if (cross > limitCross + 1e-9) why = String.format(Locale.ROOT, "%.1f kn across your course (your limit is %.1f)", cross, limitCross);
        return new Trip(departure, runs, why == null, why, t, opp, cross);
    }

    static double norm(double deg) {
        double d = deg % 360;
        return d < 0 ? d + 360 : d;
    }
}
