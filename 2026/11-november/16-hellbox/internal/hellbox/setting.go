package hellbox

import "sort"

// Costs: how much each substitution hurts the look is its Cost; buying a sort costs far more
// than any substitution, so a setting only buys what it can't do without.
const buyCost = 10000

// maxTries caps the combinations of multi-sort substitutions tried for one forme.
const maxTries = 4000

// Used is one substitution in a setting: how many times a glyph was set some other way.
type Used struct {
	For   Glyph
	Sorts []Glyph
	Count int
	Note  string
}

// A Setting is one forme: some pages set together, and how.
type Setting struct {
	Pages     []int
	OK        bool // could be set with the case (plus Buy, if buying was allowed)
	Looks     int  // total substitution cost
	Subs      []Used
	Ligatures map[Glyph]int // ligature sorts used
	Buy       map[Glyph]int // sorts to buy
	Spare     map[Glyph]int // sorts left in the case afterwards
	Letters   int           // characters set
}

// Solve sets the given pages in one forme. With buy, it works out the fewest sorts to buy to
// make it possible; without, it reports whether the case is enough.
func Solve(c *Case, subs []Sub, pages []Page, which []int, buy bool) Setting {
	need := map[Glyph]int{}
	ligs := map[Glyph]int{}
	for _, i := range which {
		for g, k := range pages[i].Need {
			need[g] += k
		}
		for g, k := range pages[i].Ligs {
			ligs[g] += k
		}
	}
	supply := map[Glyph]int{}
	for g, k := range c.Count {
		supply[g] = k
	}
	out := Setting{Pages: append([]int(nil), which...), Ligatures: map[Glyph]int{}, Buy: map[Glyph]int{}}
	for _, k := range need {
		out.Letters += k
	}
	// Ligatures first: a ligature sort has no other use, so using one never hurts.
	for _, l := range Ligatures {
		u := min(ligs[l], supply[l])
		if u <= 0 {
			continue
		}
		out.Ligatures[l] = u
		supply[l] -= u
		for _, r := range string(l) {
			need[Glyph(r)] -= u
		}
	}
	// Substitutions that use more than one sort are tried in every combination of counts
	// (there are few of them); the rest is a min-cost flow.
	var multi []Sub
	var single []Sub
	for _, s := range subs {
		if need[s.For] <= 0 {
			continue
		}
		if len(s.Use) == 1 {
			single = append(single, s)
		} else {
			multi = append(multi, s)
		}
	}
	ranges := make([][]int, len(multi))
	tries := 1
	for i, s := range multi {
		hi := need[s.For]
		if !buy {
			for _, u := range s.Use {
				per := 0
				for _, v := range s.Use {
					if v == u {
						per++
					}
				}
				hi = min(hi, supply[u]/per)
			}
		}
		ranges[i] = spread(hi, 12)
		tries *= len(ranges[i])
	}
	if tries > maxTries {
		for i := range ranges {
			ranges[i] = spread(ranges[i][len(ranges[i])-1], 3)
		}
	}
	best := Setting{}
	bestCost := -1
	ks := make([]int, len(multi))
	var walk func(int)
	walk = func(i int) {
		if i < len(multi) {
			for _, k := range ranges[i] {
				ks[i] = k
				walk(i + 1)
			}
			return
		}
		s, cost := settle(need, supply, multi, ks, single, buy)
		if s.OK && (bestCost < 0 || cost < bestCost) {
			best, bestCost = s, cost
		}
	}
	walk(0)
	if bestCost < 0 {
		out.OK = false
		return out
	}
	out.OK = true
	out.Looks = best.Looks
	out.Subs = best.Subs
	out.Buy = best.Buy
	out.Spare = best.Spare
	return out
}

// spread returns up to n counts from 0 to hi, always including both ends.
func spread(hi, n int) []int {
	if hi <= 0 {
		return []int{0}
	}
	if hi+1 <= n {
		r := make([]int, hi+1)
		for i := range r {
			r[i] = i
		}
		return r
	}
	r := make([]int, 0, n)
	for i := 0; i < n; i++ {
		r = append(r, i*hi/(n-1))
	}
	return r
}

// settle fixes the multi-sort substitutions at ks and solves the rest as a min-cost flow.
func settle(need0, supply0 map[Glyph]int, multi []Sub, ks []int, single []Sub, buy bool) (Setting, int) {
	need := map[Glyph]int{}
	for g, k := range need0 {
		if k > 0 {
			need[g] = k
		}
	}
	supply := map[Glyph]int{}
	for g, k := range supply0 {
		supply[g] = k
	}
	res := Setting{Buy: map[Glyph]int{}, Spare: map[Glyph]int{}}
	cost := 0
	for i, s := range multi {
		k := ks[i]
		if k == 0 {
			continue
		}
		if k > need[s.For] {
			return res, 0
		}
		need[s.For] -= k
		for _, u := range s.Use {
			supply[u] -= k
		}
		res.Subs = append(res.Subs, Used{s.For, s.Use, k, s.Note})
		res.Looks += k * s.Cost
		cost += k * s.Cost
	}
	for g, k := range supply {
		if k < 0 {
			if !buy {
				return res, 0
			}
			res.Buy[g] += -k
			cost += buyCost * -k
			supply[g] = 0
		}
	}
	// Nodes: 0 source, 1 sink, then one per needed glyph, then one per sort.
	dem := sortedGlyphs(need)
	srt := sortedGlyphs(supply)
	dIdx := map[Glyph]int{}
	sIdx := map[Glyph]int{}
	for i, g := range dem {
		dIdx[g] = 2 + i
	}
	for i, g := range srt {
		sIdx[g] = 2 + len(dem) + i
	}
	net := newNetwork(2 + len(dem) + len(srt))
	total := 0
	type arc struct {
		h   [2]int
		sub *Sub
		g   Glyph
	}
	var arcs []arc
	for _, g := range dem {
		net.add(0, dIdx[g], need[g], 0)
		total += need[g]
		if j, ok := sIdx[g]; ok {
			net.add(dIdx[g], j, need[g], 0)
		}
		if buy {
			arcs = append(arcs, arc{net.add(dIdx[g], 1, need[g], buyCost), nil, g})
		}
	}
	for i := range single {
		s := &single[i]
		d, ok1 := dIdx[s.For]
		j, ok2 := sIdx[s.Use[0]]
		if ok1 && ok2 && s.Use[0] != s.For {
			arcs = append(arcs, arc{net.add(d, j, need[s.For], s.Cost), s, s.For})
		}
	}
	toSink := map[Glyph][2]int{}
	for _, g := range srt {
		toSink[g] = net.add(sIdx[g], 1, supply[g], 0)
	}
	f, c := net.minCostFlow(0, 1)
	if f < total {
		return res, 0
	}
	cost += c
	for _, a := range arcs {
		k := net.flow(a.h)
		if k == 0 {
			continue
		}
		if a.sub == nil {
			res.Buy[a.g] += k
			continue
		}
		res.Subs = append(res.Subs, Used{a.sub.For, a.sub.Use, k, a.sub.Note})
		res.Looks += k * a.sub.Cost
	}
	// What's left in the case.
	for _, g := range srt {
		res.Spare[g] = supply[g] - net.flow(toSink[g])
	}
	sort.Slice(res.Subs, func(i, j int) bool { return res.Subs[i].Count > res.Subs[j].Count })
	res.OK = true
	return res, cost
}
