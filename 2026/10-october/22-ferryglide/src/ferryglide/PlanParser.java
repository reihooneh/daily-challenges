package ferryglide;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reads a plan file strictly. Every number is range-checked, every line must match one of the
 * known forms, and errors say which line is wrong without echoing it back.
 *
 * <pre>
 * trip Botany Bay to Bate Bay
 * paddle 3.5                     # cruising speed through the water, knots
 * window 05:00 to 11:00          # earliest and latest departure to consider
 * limit opposing 1.5             # optional: most current you'll paddle against, knots
 * limit cross 2.0                # optional: most current across your course, knots
 * step 5                         # optional: minutes between departure times tried
 * station Port Hacking entrance, flood 315
 * event 04:12 slack
 * event 07:30 flood 2.1
 * event 10:41 slack
 * event 13:52 ebb 1.8
 * leg Cape Banks to Boat Harbour: 2.4 nm, course 190, offset +20, ratio 0.6
 * leg Boat Harbour to Bate Bay: 3.1 nm, course 215, offset -15, ratio 0.4, flood 300
 * </pre>
 */
public final class PlanParser {
    public static final int MAX_BYTES = 64 * 1024;
    public static final int MAX_LINE = 200;
    public static final int MAX_LEGS = 30;
    public static final int MAX_EVENTS = 40;

    /** A problem with the plan file, with the line it was found on. */
    public static final class PlanException extends Exception {
        private static final long serialVersionUID = 1L;

        public PlanException(String message) {
            super(message);
        }
    }

    private static final String NAME = "([\\p{L}\\p{N}][\\p{L}\\p{N} .,'()/&-]{0,59})";
    private static final String NAME_NO_COMMA = "([\\p{L}\\p{N}][\\p{L}\\p{N} .'()/&-]{0,59})";
    private static final String NUM = "(\\d{1,3}(?:\\.\\d{1,3})?)";
    private static final String TIME = "(\\d{1,2}):(\\d{2})";
    private static final Pattern TRIP = Pattern.compile("trip " + NAME);
    private static final Pattern PADDLE = Pattern.compile("paddle " + NUM + "(?: ?kn)?");
    private static final Pattern WINDOW = Pattern.compile("window " + TIME + " to " + TIME);
    private static final Pattern LIMIT = Pattern.compile("limit (opposing|cross) " + NUM + "(?: ?kn)?");
    private static final Pattern STEP = Pattern.compile("step (\\d{1,2})");
    private static final Pattern STATION = Pattern.compile("station " + NAME_NO_COMMA + ", flood " + NUM);
    private static final Pattern EVENT = Pattern.compile("event " + TIME + " (slack|flood " + NUM + "|ebb " + NUM + ")");
    private static final Pattern LEG = Pattern.compile("leg " + NAME_NO_COMMA + ": " + NUM
            + " ?nm, course " + NUM + ", offset ([+-]?\\d{1,3}), ratio " + NUM + "(?:, flood " + NUM + ")?");

    private PlanParser() {}

    public static Plan parse(String text) throws PlanException {
        if (text.length() > MAX_BYTES) throw new PlanException("the plan is larger than 64 KB");
        String trip = "Trip";
        double paddle = -1;
        int wStart = -1, wEnd = -1, step = 5;
        double maxOpp = 1.5, maxCross = 2.0;
        String stationName = null;
        double stationFlood = 0;
        List<Plan.Event> events = new ArrayList<>();
        List<Plan.Leg> legs = new ArrayList<>();
        String[] lines = text.split("\r?\n", -1);
        int lastEvent = -1, dayShift = 0;
        for (int i = 0; i < lines.length; i++) {
            int n = i + 1;
            String raw = lines[i];
            if (raw.length() > MAX_LINE) throw new PlanException("line " + n + " is longer than " + MAX_LINE + " characters");
            for (int k = 0; k < raw.length(); k++) {
                char c = raw.charAt(k);
                if ((Character.isISOControl(c) && c != '\t') || (c >= '‪' && c <= '‮') || (c >= '⁦' && c <= '⁩')
                        || c == '‎' || c == '‏') {
                    throw new PlanException("line " + n + " contains control or hidden direction characters");
                }
            }
            int hash = raw.indexOf('#');
            String line = (hash >= 0 ? raw.substring(0, hash) : raw).strip().replaceAll("[ \\t]+", " ");
            if (line.isEmpty()) continue;
            String low = line.toLowerCase(Locale.ROOT);
            Matcher m;
            if ((m = TRIP.matcher(line)).matches()) {
                trip = m.group(1);
            } else if ((m = PADDLE.matcher(low)).matches()) {
                paddle = number(m.group(1), 0.5, 8, "paddle speed", n);
            } else if ((m = WINDOW.matcher(low)).matches()) {
                wStart = time(m.group(1), m.group(2), n);
                wEnd = time(m.group(3), m.group(4), n);
                if (wEnd < wStart) wEnd += 24 * 60;
                if (wEnd - wStart > 18 * 60) throw new PlanException("line " + n + ": the departure window is longer than 18 hours");
            } else if ((m = LIMIT.matcher(low)).matches()) {
                double v = number(m.group(2), 0, 10, "limit", n);
                if (m.group(1).equals("opposing")) maxOpp = v; else maxCross = v;
            } else if ((m = STEP.matcher(low)).matches()) {
                step = (int) number(m.group(1), 1, 60, "step", n);
            } else if ((m = STATION.matcher(line)).matches()) {
                if (stationName != null) throw new PlanException("line " + n + ": only one reference station is allowed");
                stationName = m.group(1);
                stationFlood = direction(m.group(2), n);
            } else if ((m = EVENT.matcher(low)).matches()) {
                if (events.size() >= MAX_EVENTS) throw new PlanException("line " + n + ": more than " + MAX_EVENTS + " current events");
                int t = time(m.group(1), m.group(2), n) + dayShift;
                // Tables run past midnight: a time earlier than the last one is the next day.
                if (t <= lastEvent) {
                    dayShift += 24 * 60;
                    t += 24 * 60;
                }
                if (t <= lastEvent) throw new PlanException("line " + n + ": events must be in time order");
                if (t > 48 * 60) throw new PlanException("line " + n + ": the current table runs past the next day");
                double speed = 0;
                if (m.group(4) != null) speed = number(m.group(4), 0.05, 10, "flood speed", n);
                if (m.group(5) != null) speed = -number(m.group(5), 0.05, 10, "ebb speed", n);
                events.add(new Plan.Event(t, speed));
                lastEvent = t;
            } else if ((m = LEG.matcher(line)).matches()) {
                if (legs.size() >= MAX_LEGS) throw new PlanException("line " + n + ": more than " + MAX_LEGS + " legs");
                double dist = number(m.group(2), 0.05, 50, "distance", n);
                double course = direction(m.group(3), n);
                int offset = Integer.parseInt(m.group(4));
                if (offset < -180 || offset > 180) throw new PlanException("line " + n + ": offset must be within 180 minutes");
                double ratio = number(m.group(5), 0, 3, "ratio", n);
                double flood = m.group(6) != null ? direction(m.group(6), n) : Double.NaN;
                legs.add(new Plan.Leg(m.group(1), dist, course, offset, ratio, flood));
            } else {
                String word = low.split(" ", 2)[0];
                throw new PlanException("line " + n + (switch (word) {
                    case "trip", "paddle", "window", "limit", "step", "station", "event", "leg" -> ": the " + word + " line isn't in the expected form (see the README)";
                    default -> ": lines start with trip, paddle, window, limit, step, station, event or leg";
                }));
            }
        }
        if (paddle < 0) throw new PlanException("the plan needs a paddle line (your speed through the water)");
        if (wStart < 0) throw new PlanException("the plan needs a window line (when you could leave)");
        if (stationName == null) throw new PlanException("the plan needs a station line");
        if (legs.isEmpty()) throw new PlanException("the plan needs at least one leg");
        checkEvents(events);
        List<Plan.Leg> filled = new ArrayList<>();
        for (Plan.Leg l : legs) {
            filled.add(Double.isNaN(l.floodSet()) ? new Plan.Leg(l.name(), l.distance(), l.course(), l.offset(), l.ratio(), stationFlood) : l);
        }
        return new Plan(trip, paddle, wStart, wEnd, step, maxOpp, maxCross,
                new Plan.Station(stationName, stationFlood, List.copyOf(events)), List.copyOf(filled));
    }

    /** A current table must alternate slack, maximum, slack, ... with floods and ebbs taking turns. */
    private static void checkEvents(List<Plan.Event> events) throws PlanException {
        if (events.size() < 3) throw new PlanException("the current table needs at least 3 events (slack, maximum, slack)");
        double lastMax = 0;
        for (int i = 0; i < events.size(); i++) {
            Plan.Event e = events.get(i);
            if (i > 0 && e.slack() == events.get(i - 1).slack()) {
                throw new PlanException("current events must alternate between slack and a maximum (event " + (i + 1) + ")");
            }
            if (!e.slack()) {
                if (lastMax != 0 && Math.signum(lastMax) == Math.signum(e.speed())) {
                    throw new PlanException("floods and ebbs must take turns (event " + (i + 1) + ")");
                }
                lastMax = e.speed();
            }
        }
    }

    private static double number(String s, double lo, double hi, String what, int line) throws PlanException {
        double v = Double.parseDouble(s);
        if (!(v >= lo && v <= hi)) throw new PlanException("line " + line + ": " + what + " must be between " + fmt(lo) + " and " + fmt(hi));
        return v;
    }

    private static double direction(String s, int line) throws PlanException {
        return number(s, 0, 359.999, "direction", line);
    }

    private static int time(String h, String m, int line) throws PlanException {
        int hh = Integer.parseInt(h), mm = Integer.parseInt(m);
        if (hh > 23 || mm > 59) throw new PlanException("line " + line + ": times are 00:00 to 23:59");
        return hh * 60 + mm;
    }

    private static String fmt(double v) {
        return v == Math.rint(v) ? String.valueOf((long) v) : String.valueOf(v);
    }
}
