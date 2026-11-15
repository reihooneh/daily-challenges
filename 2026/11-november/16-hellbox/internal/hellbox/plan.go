package hellbox

import (
	"sort"
)

// ExactPages is the largest job Hellbox plans exactly; bigger jobs are packed first-fit.
const ExactPages = 14

// A Plan groups the pages into formes: each forme is set, printed, and distributed back into
// the case before the next is set.
type Plan struct {
	Formes     []Setting
	Alone      []int // pages that can't be set even on their own (they need more type)
	LowerBound int   // no plan can use fewer formes than this
	Exact      bool  // the plan was proved to use the fewest formes
	Checks     int   // settings tried
}

type planner struct {
	c      *Case
	subs   []Sub
	pages  []Page
	per    int
	memo   map[uint64]bool
	checks int
}

func (p *planner) fits(mask uint64, list []int) bool {
	if ok, seen := p.memo[mask]; seen {
		return ok
	}
	p.checks++
	ok := Solve(p.c, p.subs, p.pages, list, false).OK
	p.memo[mask] = ok
	return ok
}

// PlanJob finds the fewest formes for the job, given how many pages fit on the press at once.
func PlanJob(c *Case, subs []Sub, pages []Page, perForme int) Plan {
	p := &planner{c: c, subs: subs, pages: pages, per: max(1, perForme), memo: map[uint64]bool{}}
	var ok []int
	var plan Plan
	for i := range pages {
		if Solve(c, subs, pages, []int{i}, false).OK {
			ok = append(ok, i)
		} else {
			plan.Alone = append(plan.Alone, i)
		}
	}
	plan.LowerBound = lowerBound(c, subs, pages, ok, p.per)
	// Biggest pages first: they're the hardest to fit.
	sort.SliceStable(ok, func(a, b int) bool { return size(pages[ok[a]]) > size(pages[ok[b]]) })

	var groups [][]int
	if len(ok) <= ExactPages {
		groups = p.exact(ok)
		plan.Exact = true
	} else {
		groups = p.firstFit(ok)
		plan.Exact = len(groups) == plan.LowerBound
	}
	for _, g := range groups {
		sort.Ints(g)
	}
	sort.Slice(groups, func(a, b int) bool { return groups[a][0] < groups[b][0] })
	for _, g := range groups {
		plan.Formes = append(plan.Formes, Solve(c, subs, pages, g, false))
	}
	plan.Checks = p.checks
	return plan
}

func size(p Page) int {
	n := 0
	for _, k := range p.Need {
		n += k
	}
	return n
}

func maskOf(list []int) uint64 {
	var m uint64
	for _, i := range list {
		m |= 1 << uint(i%64)
	}
	return m
}

// firstFit puts each page in the first forme it fits, opening a new one when none does.
func (p *planner) firstFit(order []int) [][]int {
	var groups [][]int
	for _, i := range order {
		placed := false
		for g := range groups {
			if len(groups[g]) < p.per {
				try := append(append([]int(nil), groups[g]...), i)
				if p.fitsList(try) {
					groups[g] = try
					placed = true
					break
				}
			}
		}
		if !placed {
			groups = append(groups, []int{i})
		}
	}
	return groups
}

func (p *planner) fitsList(list []int) bool {
	if len(p.pages) <= 64 {
		return p.fits(maskOf(list), list)
	}
	p.checks++
	return Solve(p.c, p.subs, p.pages, list, false).OK
}

// exact searches every way of grouping the pages (branch and bound), starting from first-fit.
func (p *planner) exact(order []int) [][]int {
	best := p.firstFit(order)
	cur := [][]int{}
	var dfs func(int)
	dfs = func(k int) {
		if len(cur) >= len(best) {
			return
		}
		if k == len(order) {
			best = make([][]int, len(cur))
			for i, g := range cur {
				best[i] = append([]int(nil), g...)
			}
			return
		}
		i := order[k]
		for g := range cur {
			if len(cur[g]) < p.per {
				try := append(append([]int(nil), cur[g]...), i)
				if p.fitsList(try) {
					saved := cur[g]
					cur[g] = try
					dfs(k + 1)
					cur[g] = saved
				}
			}
		}
		// Or start a new forme (only if that could still beat the best).
		if len(cur)+1 < len(best) {
			cur = append(cur, []int{i})
			dfs(k + 1)
			cur = cur[:len(cur)-1]
		}
	}
	dfs(0)
	return best
}

// lowerBound: the press holds `per` pages, and every forme can set a glyph at most as many
// times as there are sorts able to print it (including substitutes).
func lowerBound(c *Case, subs []Sub, pages []Page, list []int, per int) int {
	if len(list) == 0 {
		return 0
	}
	lb := (len(list) + per - 1) / per
	need := map[Glyph]int{}
	for _, i := range list {
		for g, k := range pages[i].Need {
			need[g] += k
		}
	}
	for g, k := range need {
		capacity := c.Count[g]
		for _, s := range subs {
			if s.For == g {
				capacity += c.Count[s.Use[0]] / len(s.Use)
			}
		}
		// A ligature can stand in for its letters.
		for _, l := range Ligatures {
			for _, r := range string(l) {
				if Glyph(r) == g {
					capacity += c.Count[l]
				}
			}
		}
		if capacity == 0 {
			continue
		}
		lb = max(lb, (k+capacity-1)/capacity)
	}
	return lb
}

// Shopping works out what to buy so the job fits in `formes` formes of consecutive pages: for
// each forme, the fewest sorts to buy; since type is reused between formes, the list is the
// largest number needed of each sort by any forme.
func Shopping(c *Case, subs []Sub, pages []Page, perForme, formes int) map[Glyph]int {
	out := map[Glyph]int{}
	n := len(pages)
	if formes < 1 {
		formes = 1
	}
	size := (n + formes - 1) / formes
	size = min(max(size, 1), max(perForme, 1))
	for start := 0; start < n; start += size {
		var g []int
		for i := start; i < min(n, start+size); i++ {
			g = append(g, i)
		}
		s := Solve(c, subs, pages, g, true)
		for k, v := range s.Buy {
			out[k] = max(out[k], v)
		}
	}
	return out
}
