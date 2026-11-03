package gapsmith;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Finds where to cut the rails. A reversing section is a run of track, cut off from the rest by
 * insulated joiners on both rails at every join where it meets the rest, and fed by an
 * auto-reverser that flips its polarity as a train crosses a gap. A plan works when:
 * <ul>
 *   <li>the rest of the layout can be wired with one consistent polarity (no odd loops left),</li>
 *   <li>each reversing section is consistent within itself, and</li>
 *   <li>each reversing section is longer than the longest train, so a train never bridges both
 *       ends at once (that would short the auto-reverser).</li>
 * </ul>
 * Among working plans it prefers the fewest auto-reversers, then the fewest cuts, then the
 * shortest sections. Small layouts are searched completely: every connected run of up to
 * {@link #MAX_RUN} sections, alone or in pairs.
 */
public final class Planner {
    private Planner() {}

    public static final int MAX_RUN = 8;
    public static final int MAX_CANDIDATES = 300_000;
    public static final int MAX_PAIRS = 600;

    /** A reversing section: its sections and the joins that need cutting. */
    public record Reverser(List<Integer> sections, List<Integer> cuts, double length) {}

    public record Plan(
            boolean alreadyFine,
            List<Integer> loop, // an odd loop found before any fix (empty if none)
            List<Reverser> reversers, // empty if already fine or nothing works
            int[] polarity, // per section, +1/-1 for wired track, 0 inside a reversing section
            boolean searchedAll, // false if the candidate limit was hit
            String problem) {} // why nothing works, or null

    record Candidate(boolean[] in, List<Integer> sections, List<Integer> cuts, double length) {}

    public static Plan plan(Layout l) {
        List<List<Integer>> adj = Polarity.adjacency(l);
        List<Integer> loop = new ArrayList<>();
        int[] c = Polarity.colour(l, adj, null, loop);
        if (c != null) return new Plan(true, List.of(), List.of(), c, true, null);

        // Every connected run of up to MAX_RUN sections (each found once).
        List<Candidate> fits = new ArrayList<>();
        int n = l.sections.size();
        int[] count = {0};
        boolean[] in = new boolean[n];
        for (int v = 0; v < n && count[0] < MAX_CANDIDATES; v++) {
            in[v] = true;
            List<Integer> sub = new ArrayList<>(List.of(v));
            List<Integer> ext = new ArrayList<>();
            for (int u : neighbours(l, adj, v)) if (u > v && !ext.contains(u)) ext.add(u);
            grow(l, adj, sub, ext, v, in, fits, count);
            in[v] = false;
        }
        boolean searchedAll = count[0] < MAX_CANDIDATES;

        // One reverser.
        Candidate best = null;
        int[] bestColour = null;
        for (Candidate cd : fits) {
            if (best != null && better(best, cd)) continue;
            int[] col = Polarity.colour(l, adj, cd.in(), null);
            if (col != null && (best == null || better(cd, best))) {
                best = cd;
                bestColour = col;
            }
        }
        if (best != null) return new Plan(false, loop, List.of(reverser(best)), wired(bestColour, best.in()), searchedAll, null);

        // Two reversers (a wye and a loop, say), kept apart so each has its own auto-reverser.
        List<Candidate> pool = new ArrayList<>(fits);
        pool.sort(Comparator.comparingInt((Candidate x) -> x.cuts().size()).thenComparingDouble(Candidate::length));
        if (pool.size() > MAX_PAIRS) pool = pool.subList(0, MAX_PAIRS);
        Candidate[] bestPair = null;
        int[] pairColour = null;
        int bestCuts = Integer.MAX_VALUE;
        for (int i = 0; i < pool.size(); i++) {
            for (int j = i + 1; j < pool.size(); j++) {
                Candidate a = pool.get(i);
                Candidate b = pool.get(j);
                int cuts = a.cuts().size() + b.cuts().size();
                if (cuts >= bestCuts || !apart(l, a, b)) continue;
                boolean[] both = new boolean[n];
                for (int k = 0; k < n; k++) both[k] = a.in()[k] || b.in()[k];
                int[] col = Polarity.colour(l, adj, both, null);
                if (col != null) {
                    bestCuts = cuts;
                    bestPair = new Candidate[] {a, b};
                    pairColour = wired(col, both);
                }
            }
        }
        if (bestPair != null) {
            return new Plan(false, loop, List.of(reverser(bestPair[0]), reverser(bestPair[1])), pairColour, searchedAll && fits.size() <= MAX_PAIRS, null);
        }
        double longestRun = fits.stream().mapToDouble(Candidate::length).max().orElse(0);
        String why = fits.isEmpty()
                ? "no run of track around the reversing loop is longer than your longest train (" + Layout.metres(l.train) + ")"
                : "no set of one or two reversing sections of up to " + MAX_RUN + " pieces fixes every short circuit (the longest that fits your train is "
                        + Layout.metres(longestRun) + ")";
        return new Plan(false, loop, List.of(), new int[n], searchedAll, why);
    }

    private static boolean better(Candidate a, Candidate b) {
        if (a.cuts().size() != b.cuts().size()) return a.cuts().size() < b.cuts().size();
        if (a.length() != b.length()) return a.length() < b.length();
        return a.sections().toString().compareTo(b.sections().toString()) < 0;
    }

    private static boolean apart(Layout l, Candidate a, Candidate b) {
        for (int k = 0; k < a.in().length; k++) if (a.in()[k] && b.in()[k]) return false;
        for (Layout.Join jn : l.joins) {
            int x = jn.a().section();
            int y = jn.b().section();
            if ((a.in()[x] && b.in()[y]) || (a.in()[y] && b.in()[x])) return false;
        }
        return true;
    }

    private static int[] wired(int[] colour, boolean[] reversing) {
        int[] out = colour.clone();
        for (int i = 0; i < out.length; i++) if (reversing[i]) out[i] = 0;
        return out;
    }

    private static Reverser reverser(Candidate c) {
        return new Reverser(c.sections(), c.cuts(), c.length());
    }

    private static List<Integer> neighbours(Layout l, List<List<Integer>> adj, int v) {
        List<Integer> out = new ArrayList<>();
        for (int j : adj.get(v)) {
            int u = l.joins.get(j).other(v);
            if (u != v && !out.contains(u)) out.add(u);
        }
        return out;
    }

    /** ESU enumeration (Wernicke 2006): each connected set is reached exactly once. */
    private static void grow(Layout l, List<List<Integer>> adj, List<Integer> sub, List<Integer> ext, int root, boolean[] in,
            List<Candidate> fits, int[] count) {
        if (++count[0] > MAX_CANDIDATES) return;
        consider(l, adj, sub, in, fits);
        if (sub.size() == MAX_RUN) return;
        List<Integer> rest = new ArrayList<>(ext);
        while (!rest.isEmpty()) {
            int w = rest.remove(rest.size() - 1);
            List<Integer> next = new ArrayList<>(rest);
            for (int u : neighbours(l, adj, w)) {
                if (u <= root || in[u] || next.contains(u)) continue;
                boolean nearSub = false;
                for (int s : sub) if (neighbours(l, adj, s).contains(u)) nearSub = true;
                if (!nearSub) next.add(u);
            }
            in[w] = true;
            sub.add(w);
            grow(l, adj, sub, next, root, in, fits, count);
            sub.remove(sub.size() - 1);
            in[w] = false;
            if (count[0] > MAX_CANDIDATES) return;
        }
    }

    /** Keeps a run if it can hold the train and is consistent within itself. */
    private static void consider(Layout l, List<List<Integer>> adj, List<Integer> sub, boolean[] in, List<Candidate> fits) {
        double len = 0;
        for (int s : sub) len += l.sections.get(s).length();
        if (len <= l.train) return;
        if (sub.size() == l.sections.size()) return; // the whole layout can't be its own reversing section
        boolean[] copy = in.clone();
        if (!Polarity.consistentWithin(l, adj, copy)) return;
        List<Integer> cuts = new ArrayList<>();
        for (int j = 0; j < l.joins.size(); j++) {
            Layout.Join jn = l.joins.get(j);
            if (copy[jn.a().section()] != copy[jn.b().section()]) cuts.add(j);
        }
        if (cuts.isEmpty()) return; // not connected to anything: cutting nothing fixes nothing
        List<Integer> sorted = new ArrayList<>(sub);
        sorted.sort(null);
        fits.add(new Candidate(copy, sorted, cuts, len));
    }
}
