package gapsmith;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Rail polarity as a signed graph. Each section gets a polarity, +1 or -1 (which of its rails is
 * the "red" one). A join where left rails meet left rails says the two sections have the same
 * polarity; a join where they cross (two "a" ends, or two "b" ends, nose to nose) says they're
 * opposite. A short circuit is a loop of joins with an odd number of crossings: the rules
 * can't all hold, which is exactly a reversing loop.
 */
public final class Polarity {
    private Polarity() {}

    /** For each section, the joins that touch it. */
    public static List<List<Integer>> adjacency(Layout l) {
        List<List<Integer>> adj = new ArrayList<>();
        for (int i = 0; i < l.sections.size(); i++) adj.add(new ArrayList<>());
        for (int j = 0; j < l.joins.size(); j++) {
            Layout.Join jn = l.joins.get(j);
            adj.get(jn.a().section()).add(j);
            if (jn.b().section() != jn.a().section()) adj.get(jn.b().section()).add(j);
        }
        return adj;
    }

    /**
     * Gives every section not in {@code skip} a polarity that satisfies every join between such
     * sections, or returns null if that's impossible. On failure, {@code conflict} (if not null)
     * receives one odd loop of joins, in order around the loop.
     */
    public static int[] colour(Layout l, List<List<Integer>> adj, boolean[] skip, List<Integer> conflict) {
        int n = l.sections.size();
        int[] c = new int[n];
        int[] parentJoin = new int[n];
        int[] depth = new int[n];
        for (int start = 0; start < n; start++) {
            if (c[start] != 0 || (skip != null && skip[start])) continue;
            c[start] = 1;
            parentJoin[start] = -1;
            depth[start] = 0;
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(start);
            while (!queue.isEmpty()) {
                int u = queue.poll();
                for (int j : adj.get(u)) {
                    Layout.Join jn = l.joins.get(j);
                    int v = jn.other(u);
                    if (skip != null && skip[v]) continue;
                    int want = jn.same() ? c[u] : -c[u];
                    if (c[v] == 0) {
                        c[v] = want;
                        parentJoin[v] = j;
                        depth[v] = depth[u] + 1;
                        queue.add(v);
                    } else if (c[v] != want) {
                        if (conflict != null) oddLoop(l, parentJoin, depth, u, v, j, conflict);
                        return null;
                    }
                }
            }
        }
        return c;
    }

    /** The loop through the breadth-first tree from u and v to where their paths meet, plus join j. */
    private static void oddLoop(Layout l, int[] parentJoin, int[] depth, int u, int v, int j, List<Integer> out) {
        List<Integer> fromU = new ArrayList<>();
        List<Integer> fromV = new ArrayList<>();
        int a = u;
        int b = v;
        while (a != b) {
            if (depth[a] >= depth[b] && parentJoin[a] >= 0) {
                fromU.add(parentJoin[a]);
                a = l.joins.get(parentJoin[a]).other(a);
            } else if (parentJoin[b] >= 0) {
                fromV.add(parentJoin[b]);
                b = l.joins.get(parentJoin[b]).other(b);
            } else {
                break;
            }
        }
        out.clear();
        Collections.reverse(fromU);
        out.addAll(fromU);
        out.add(j);
        out.addAll(fromV);
    }

    /** Whether the sections in {@code inside} can share one polarity scheme among themselves. */
    public static boolean consistentWithin(Layout l, List<List<Integer>> adj, boolean[] inside) {
        boolean[] skip = new boolean[inside.length];
        for (int i = 0; i < inside.length; i++) skip[i] = !inside[i];
        return colour(l, adj, skip, null) != null;
    }
}
