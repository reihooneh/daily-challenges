package hellbox

// A small min-cost flow solver (successive shortest paths with Bellman–Ford, which is plenty
// for a few hundred nodes). Letters flow from what the text needs, through the sorts that can
// print them, to what the case holds.

type edge struct {
	to, rev   int
	cap, cost int
}

type network struct {
	adj [][]edge
}

func newNetwork(n int) *network {
	return &network{adj: make([][]edge, n)}
}

// add returns a handle (node, index) to read the edge's flow later.
func (g *network) add(from, to, cap, cost int) [2]int {
	g.adj[from] = append(g.adj[from], edge{to, len(g.adj[to]), cap, cost})
	g.adj[to] = append(g.adj[to], edge{from, len(g.adj[from]) - 1, 0, -cost})
	return [2]int{from, len(g.adj[from]) - 1}
}

// flow on an edge added with add: what's on its reverse edge.
func (g *network) flow(h [2]int) int {
	e := g.adj[h[0]][h[1]]
	return g.adj[e.to][e.rev].cap
}

// minCostFlow sends as much as it can from s to t, as cheaply as possible.
func (g *network) minCostFlow(s, t int) (flow, cost int) {
	n := len(g.adj)
	const inf = 1 << 60
	dist := make([]int, n)
	inQ := make([]bool, n)
	prevNode := make([]int, n)
	prevEdge := make([]int, n)
	for {
		for i := range dist {
			dist[i] = inf
		}
		dist[s] = 0
		queue := []int{s}
		inQ[s] = true
		for len(queue) > 0 {
			u := queue[0]
			queue = queue[1:]
			inQ[u] = false
			for i, e := range g.adj[u] {
				if e.cap > 0 && dist[u]+e.cost < dist[e.to] {
					dist[e.to] = dist[u] + e.cost
					prevNode[e.to] = u
					prevEdge[e.to] = i
					if !inQ[e.to] {
						inQ[e.to] = true
						queue = append(queue, e.to)
					}
				}
			}
		}
		if dist[t] == inf {
			return flow, cost
		}
		push := inf
		for v := t; v != s; v = prevNode[v] {
			if c := g.adj[prevNode[v]][prevEdge[v]].cap; c < push {
				push = c
			}
		}
		for v := t; v != s; v = prevNode[v] {
			e := &g.adj[prevNode[v]][prevEdge[v]]
			e.cap -= push
			g.adj[v][e.rev].cap += push
		}
		flow += push
		cost += push * dist[t]
	}
}
