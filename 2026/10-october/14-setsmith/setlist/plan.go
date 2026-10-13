package setlist

import (
	"fmt"
	"math"
	"math/bits"
	"sort"
	"strings"
)

// Points: what the planner tries to keep small. One point is one second of dead air.
const (
	EnergyWeight = 20.0  // per unit of squared distance from the ideal energy at that point
	DropWant     = 600.0 // leaving out a "want" song is as bad as ten minutes of tuning
	DropMaybe    = 60.0
)

// Change is what happens on stage between two songs.
type Change struct {
	Secs  int      // retuning, capo and swap time (the songs' gap is separate)
	Notes []string // "Mia retunes to dropD", ...
}

// ChangeBetween works out the changeover from song a to song b. Players change in
// parallel, so the time is the slowest player's. A player who sits out either song
// can get ready meanwhile, so costs nothing.
func (g *Gig) ChangeBetween(a, b *Song) Change {
	var c Change
	players := make([]string, 0, len(b.Parts))
	for p := range b.Parts {
		players = append(players, p)
	}
	sort.Strings(players)
	for _, p := range players {
		to := b.Parts[p]
		from, ok := a.Parts[p]
		if !ok || from == to {
			continue
		}
		secs, note := 0, ""
		switch {
		case from.Name != to.Name && g.Spares[p][to.Name]:
			secs, note = g.Swap, fmt.Sprintf("%s swaps to the spare in %s", p, to.Name)
		case from.Name != to.Name && g.Spares[p][from.Name]:
			secs, note = g.Swap, fmt.Sprintf("%s swaps back to the main instrument in %s", p, to.Name)
		case from.Name != to.Name:
			secs, note = g.Retune, fmt.Sprintf("%s retunes to %s", p, to.Name)
		case to.Capo == 0:
			secs, note = g.CapoMove, fmt.Sprintf("%s takes the capo off", p)
		case from.Capo == 0:
			secs, note = g.CapoMove, fmt.Sprintf("%s puts a capo on fret %d", p, to.Capo)
		default:
			secs, note = g.CapoMove, fmt.Sprintf("%s moves the capo to fret %d", p, to.Capo)
		}
		if secs > c.Secs {
			c.Secs = secs
		}
		c.Notes = append(c.Notes, note)
	}
	return c
}

// TargetEnergy is the shape of a good set: open strong, breathe in the middle, build to
// the end. x runs from 0 (start) to 1 (end of the music time).
func TargetEnergy(x float64) float64 {
	x = math.Max(0, math.Min(1, x))
	if x < 0.55 {
		return 4.0 + (2.8-4.0)*x/0.55
	}
	return 2.8 + (5.0-2.8)*(x-0.55)/0.45
}

// Plan is a running order and how it scores.
type Plan struct {
	Order      []int    // song indexes, in playing order
	Left       []int    // songs not played
	Changes    []Change // Changes[i] is before Order[i] (Changes[0] is empty)
	Total      int      // seconds from first note to last, with gaps and changes
	ChangeSecs int
	EnergyCost float64
	DropCost   float64
	Score      float64
	Budget     int // music time available: slot minus reserve
}

// NoPlanError explains why nothing fits.
type NoPlanError struct{ Reasons []string }

func (e *NoPlanError) Error() string {
	return "no running order fits: " + strings.Join(e.Reasons, "; ")
}

type tables struct {
	n        int
	change   [][]int
	allowed  [][]bool
	canStart []bool
	musicDur []int32 // music seconds of each subset
	mustMask int
	closer   int
	budget   int
}

func (g *Gig) tables() *tables {
	n := len(g.Songs)
	t := &tables{n: n, closer: -1, budget: g.Slot - g.Reserve}
	index := map[string]int{}
	for i, s := range g.Songs {
		index[strings.ToLower(s.Title)] = i
	}
	next := make([]int, n)
	prev := make([]int, n)
	for i := range next {
		next[i], prev[i] = -1, -1
	}
	for i, s := range g.Songs {
		if s.Then != "" {
			j := index[strings.ToLower(s.Then)]
			next[i], prev[j] = j, i
		}
		if s.Priority == Must {
			t.mustMask |= 1 << i
		}
		if s.Closer {
			t.closer = i
		}
	}
	// Songs joined by a segue stand or fall together: if either is a must, both are.
	for changed := true; changed; {
		changed = false
		for i := 0; i < n; i++ {
			for _, j := range []int{next[i], prev[i]} {
				if j >= 0 && t.mustMask&(1<<i) != 0 && t.mustMask&(1<<j) == 0 {
					t.mustMask |= 1 << j
					changed = true
				}
			}
		}
	}
	t.change = make([][]int, n)
	t.allowed = make([][]bool, n)
	t.canStart = make([]bool, n)
	opener := -1
	for i, s := range g.Songs {
		if s.Opener {
			opener = i
		}
	}
	for a := 0; a < n; a++ {
		t.change[a] = make([]int, n)
		t.allowed[a] = make([]bool, n)
		t.canStart[a] = prev[a] < 0 && (opener < 0 || opener == a)
		for b := 0; b < n; b++ {
			if a == b || b == opener || a == t.closer {
				continue
			}
			ok := (next[a] < 0 || next[a] == b) && (prev[b] < 0 || prev[b] == a)
			t.allowed[a][b] = ok
			t.change[a][b] = g.ChangeBetween(&g.Songs[a], &g.Songs[b]).Secs
		}
	}
	t.musicDur = make([]int32, 1<<n)
	for m := 1; m < 1<<n; m++ {
		low := bits.TrailingZeros(uint(m))
		t.musicDur[m] = t.musicDur[m&(m-1)] + int32(g.Songs[low].Secs)
	}
	return t
}

// fits says whether a set of songs, with a gap before each song but the first, fits the
// music time.
func (g *Gig) fits(t *tables, mask int) bool {
	return int(t.musicDur[mask])+g.Gap*(bits.OnesCount(uint(mask))-1) <= t.budget
}

// energyCost scores song s played after the songs in `before`.
func (g *Gig) energyCost(t *tables, s int, before int) float64 {
	mid := float64(t.musicDur[before]) + float64(g.Songs[s].Secs)/2
	d := float64(g.Songs[s].Energy) - TargetEnergy(mid/float64(t.budget))
	return EnergyWeight * d * d
}

func (g *Gig) dropCost(mask int) float64 {
	c := 0.0
	for i, s := range g.Songs {
		if mask&(1<<i) == 0 {
			switch s.Priority {
			case Want:
				c += DropWant
			case Maybe:
				c += DropMaybe
			}
		}
	}
	return c
}

// Solve finds the best running order exactly, by dynamic programming over
// (songs played so far, last song, hard songs in a row).
func (g *Gig) Solve() (*Plan, error) {
	t := g.tables()
	n, runs := t.n, g.BeltLimit+1
	size := (1 << n) * n * runs
	cost := make([]float64, size)
	from := make([]int32, size)
	for i := range cost {
		cost[i] = math.Inf(1)
	}
	idx := func(mask, last, run int) int { return (mask*n+last)*runs + run }

	for s := 0; s < n; s++ {
		run := 0
		if g.Songs[s].Hard {
			run = 1
		}
		if !t.canStart[s] || run >= runs || !g.fits(t, 1<<s) {
			continue
		}
		i := idx(1<<s, s, run)
		cost[i] = g.energyCost(t, s, 0)
		from[i] = -1
	}
	// Masks only grow, so visiting them in numeric order is a valid topological order.
	for mask := 1; mask < 1<<n; mask++ {
		for last := 0; last < n; last++ {
			if mask&(1<<last) == 0 {
				continue
			}
			for run := 0; run < runs; run++ {
				i := idx(mask, last, run)
				if math.IsInf(cost[i], 1) {
					continue
				}
				for b := 0; b < n; b++ {
					if mask&(1<<b) != 0 || !t.allowed[last][b] {
						continue
					}
					nr := 0
					if g.Songs[b].Hard {
						nr = run + 1
					}
					nm := mask | 1<<b
					if nr >= runs || !g.fits(t, nm) {
						continue
					}
					c := cost[i] + float64(t.change[last][b]) + g.energyCost(t, b, mask)
					j := idx(nm, b, nr)
					if c < cost[j] {
						cost[j] = c
						from[j] = int32(i)
					}
				}
			}
		}
	}

	best, bestScore := -1, math.Inf(1)
	for mask := 1; mask < 1<<n; mask++ {
		if mask&t.mustMask != t.mustMask {
			continue
		}
		drop := g.dropCost(mask)
		for last := 0; last < n; last++ {
			if mask&(1<<last) == 0 || (t.closer >= 0 && last != t.closer) || g.Songs[last].Then != "" {
				continue
			}
			for run := 0; run < runs; run++ {
				i := idx(mask, last, run)
				if s := cost[i] + drop; s < bestScore {
					best, bestScore = i, s
				}
			}
		}
	}
	if best < 0 {
		return nil, g.whyNot(t)
	}
	var order []int
	for i := best; i >= 0; i = int(from[i]) {
		order = append(order, (i/runs)%n)
	}
	for l, r := 0, len(order)-1; l < r; l, r = l+1, r-1 {
		order[l], order[r] = order[r], order[l]
	}
	return g.Score(order), nil
}

// Score describes a given order in full. Solve uses it for its answer; tests use it to
// check Solve against brute force.
func (g *Gig) Score(order []int) *Plan {
	t := g.tables()
	p := &Plan{Order: order, Budget: t.budget}
	mask := 0
	for k, s := range order {
		if k == 0 {
			p.Changes = append(p.Changes, Change{})
		} else {
			c := g.ChangeBetween(&g.Songs[order[k-1]], &g.Songs[s])
			p.Changes = append(p.Changes, c)
			p.ChangeSecs += c.Secs
			p.Total += g.Gap + c.Secs
		}
		p.EnergyCost += g.energyCost(t, s, mask)
		p.Total += g.Songs[s].Secs
		mask |= 1 << s
	}
	for i := range g.Songs {
		if mask&(1<<i) == 0 {
			p.Left = append(p.Left, i)
		}
	}
	p.DropCost = g.dropCost(mask)
	p.Score = float64(p.ChangeSecs) + p.EnergyCost + p.DropCost
	return p
}

// Valid checks an order against every hard rule; used by tests and brute force.
func (g *Gig) Valid(order []int) bool {
	t := g.tables()
	if len(order) == 0 || !t.canStart[order[0]] {
		return false
	}
	mask, run := 0, 0
	for k, s := range order {
		if mask&(1<<s) != 0 || (k > 0 && !t.allowed[order[k-1]][s]) {
			return false
		}
		mask |= 1 << s
		if g.Songs[s].Hard {
			run++
		} else {
			run = 0
		}
		if run > g.BeltLimit {
			return false
		}
	}
	last := order[len(order)-1]
	return g.fits(t, mask) && mask&t.mustMask == t.mustMask &&
		(t.closer < 0 || last == t.closer) && g.Songs[last].Then == ""
}

func (g *Gig) whyNot(t *tables) error {
	var reasons []string
	if t.mustMask != 0 && !g.fits(t, t.mustMask) {
		reasons = append(reasons, fmt.Sprintf("the must-play songs alone need %s of music time, but the slot leaves %s after the reserve",
			FormatClock(int(t.musicDur[t.mustMask])+g.Gap*(bits.OnesCount(uint(t.mustMask))-1)), FormatClock(t.budget)))
	}
	hard := 0
	for _, s := range g.Songs {
		if s.Hard && s.Priority == Must {
			hard++
		}
	}
	soft := bits.OnesCount(uint(t.mustMask)) - hard
	if hard > (soft+1)*g.BeltLimit {
		reasons = append(reasons, fmt.Sprintf("%d hard must-play songs can't be split into runs of %d with only %d other must-play songs between them",
			hard, g.BeltLimit, soft))
	}
	if len(reasons) == 0 {
		reasons = append(reasons, "the opener, closer, segues and belt-limit can't all be met together")
	}
	return &NoPlanError{reasons}
}
