package gapsmith;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A track plan: sections of track and turnouts, how their ends are joined, and the longest train.
 *
 * <p>Every line has a fixed shape and every number a range. Errors give the line number and what
 * was expected, never the line itself.
 */
public final class Layout {
    public static final int MAX_BYTES = 64 * 1024;
    public static final int MAX_LINE = 200;
    public static final int MAX_SECTIONS = 200;

    /** A piece of plain track (ends a, b) or a turnout (ends p = points, s = straight, d = diverging). */
    public record Section(String id, boolean turnout, double length) {}

    /**
     * An end of a section. "Start" ends (a, p) are where the section's rails are named from: its
     * left rail is on your left as you face into the section from that end.
     */
    public record End(int section, String name, boolean start) {
        String label(Layout l) {
            return l.sections.get(section).id() + "." + name;
        }
    }

    /** Two ends joined. {@code same} is true when the left rails meet the left rails. */
    public record Join(End a, End b, int line) {
        public boolean same() {
            return a.start() != b.start();
        }

        public int other(int s) {
            return a.section() == s ? b.section() : a.section();
        }
    }

    public static final class LayoutException extends Exception {
        private static final long serialVersionUID = 1L;

        LayoutException(int line, String msg) {
            super(line > 0 ? "line " + line + ": " + msg : msg);
        }
    }

    public final String title;
    public final double train;
    public final List<Section> sections;
    public final List<Join> joins;

    private Layout(String title, double train, List<Section> sections, List<Join> joins) {
        this.title = title;
        this.train = train;
        this.sections = List.copyOf(sections);
        this.joins = List.copyOf(joins);
    }

    public int index(String id) {
        for (int i = 0; i < sections.size(); i++) if (sections.get(i).id().equals(id)) return i;
        return -1;
    }

    private static final Pattern ID = Pattern.compile("[a-z][a-z0-9_-]{0,23}");
    private static final Pattern TITLE = Pattern.compile("[\\p{L}\\p{N}][\\p{L}\\p{N} '.,&()-]{0,59}");
    private static final Pattern LENGTH = Pattern.compile("(\\d{1,3}(?:\\.\\d{1,3})?)\\s*(m|cm|mm)");
    private static final Pattern SECTION = Pattern.compile("(track|turnout)\\s+(\\S+)\\s+(.+)");
    private static final Pattern END = Pattern.compile("([a-z][a-z0-9_-]{0,23})\\.([a-z])");
    private static final Pattern JOIN = Pattern.compile("join\\s+(\\S+)\\s+(\\S+)");

    static double length(String text, int line) throws LayoutException {
        Matcher m = LENGTH.matcher(text.trim());
        if (!m.matches()) throw new LayoutException(line, "write lengths like 1.2 m, 45 cm or 300 mm");
        double v = Double.parseDouble(m.group(1));
        double metres = switch (m.group(2)) {
            case "cm" -> v / 100;
            case "mm" -> v / 1000;
            default -> v;
        };
        if (metres < 0.01 || metres > 100) throw new LayoutException(line, "lengths must be from 1 cm to 100 m");
        return metres;
    }

    /** Reads a whole layout file. */
    public static Layout parse(String text) throws LayoutException {
        if (text.length() > MAX_BYTES) throw new LayoutException(0, "the layout file is larger than 64 KB");
        String title = "My layout";
        double train = -1;
        List<Section> sections = new ArrayList<>();
        Map<String, Integer> ids = new HashMap<>();
        List<String[]> pendingJoins = new ArrayList<>();
        List<Integer> joinLines = new ArrayList<>();
        boolean seenTitle = false;

        String[] lines = text.split("\n", -1);
        for (int i = 0; i < lines.length; i++) {
            int n = i + 1;
            String raw = lines[i].endsWith("\r") ? lines[i].substring(0, lines[i].length() - 1) : lines[i];
            if (raw.codePointCount(0, raw.length()) > MAX_LINE) throw new LayoutException(n, "is longer than " + MAX_LINE + " characters");
            for (int k = 0; k < raw.length(); k++) {
                char c = raw.charAt(k);
                int type = Character.getType(c);
                if ((Character.isISOControl(c) && c != '\t') || type == Character.FORMAT) {
                    throw new LayoutException(n, "contains a control or invisible formatting character");
                }
            }
            int hash = raw.indexOf('#');
            String line = (hash >= 0 ? raw.substring(0, hash) : raw).trim().replaceAll("\\s+", " ");
            if (line.isEmpty()) continue;
            String head = line.split(" ", 2)[0];
            switch (head) {
                case "layout" -> {
                    String t = line.length() > 7 ? line.substring(7).trim() : "";
                    if (seenTitle || !TITLE.matcher(t).matches()) {
                        throw new LayoutException(n, "the layout name comes once, in letters, digits, spaces and ' . , & ( ) - (up to 60)");
                    }
                    title = t;
                    seenTitle = true;
                }
                case "train" -> {
                    if (train >= 0) throw new LayoutException(n, "'train' comes once");
                    train = length(line.substring(5), n);
                }
                case "track", "turnout" -> {
                    Matcher m = SECTION.matcher(line);
                    if (!m.matches() || !ID.matcher(m.group(2)).matches()) {
                        throw new LayoutException(n, "write it like 'track loop1 1.8 m'; ids are lower-case letters, digits, _ or - (up to 24)");
                    }
                    if (ids.containsKey(m.group(2))) throw new LayoutException(n, "that id is already used");
                    if (sections.size() >= MAX_SECTIONS) throw new LayoutException(n, "at most " + MAX_SECTIONS + " sections");
                    ids.put(m.group(2), sections.size());
                    sections.add(new Section(m.group(2), m.group(1).equals("turnout"), length(m.group(3), n)));
                }
                case "join" -> {
                    Matcher m = JOIN.matcher(line);
                    if (!m.matches()) throw new LayoutException(n, "write it like 'join main.b t1.p'");
                    pendingJoins.add(new String[] {m.group(1), m.group(2)});
                    joinLines.add(n);
                }
                default -> throw new LayoutException(n, "lines start with layout, train, track, turnout or join");
            }
        }
        if (sections.isEmpty()) throw new LayoutException(0, "the layout has no track");
        if (train < 0) throw new LayoutException(0, "say how long your longest train is, like 'train 1.2 m'");

        List<Join> joins = new ArrayList<>();
        Map<String, Integer> used = new HashMap<>();
        for (int j = 0; j < pendingJoins.size(); j++) {
            int n = joinLines.get(j);
            End a = end(pendingJoins.get(j)[0], ids, sections, n);
            End b = end(pendingJoins.get(j)[1], ids, sections, n);
            for (End e : new End[] {a, b}) {
                String key = e.section() + "." + e.name();
                if (used.containsKey(key)) throw new LayoutException(n, "an end is joined twice (each end joins one other end)");
                used.put(key, n);
            }
            if (a.section() == b.section() && a.name().equals(b.name())) throw new LayoutException(n, "an end can't join itself");
            joins.add(new Join(a, b, n));
        }
        return new Layout(title, train, sections, joins);
    }

    private static End end(String text, Map<String, Integer> ids, List<Section> sections, int line) throws LayoutException {
        Matcher m = END.matcher(text);
        if (!m.matches()) throw new LayoutException(line, "ends are written like main.b (track ends a, b; turnout ends p, s, d)");
        Integer s = ids.get(m.group(1));
        if (s == null) throw new LayoutException(line, "joins a section that hasn't been listed above");
        boolean turnout = sections.get(s).turnout();
        String e = m.group(2);
        boolean ok = turnout ? e.equals("p") || e.equals("s") || e.equals("d") : e.equals("a") || e.equals("b");
        if (!ok) throw new LayoutException(line, turnout ? "turnouts have ends p, s and d" : "track has ends a and b");
        return new End(s, e, e.equals("a") || e.equals("p"));
    }

    /** Metres to a short human length. */
    public static String metres(double m) {
        return m < 1 ? String.format(Locale.ROOT, "%.0f cm", m * 100) : String.format(Locale.ROOT, "%.2f m", m);
    }
}
