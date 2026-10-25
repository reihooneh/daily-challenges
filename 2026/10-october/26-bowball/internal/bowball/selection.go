package bowball

import (
	"math"
	"math/rand/v2"
	"sort"
)

// Ranking orders the rowers fastest first (ties by name, so output is stable).
func Ranking(s *Session, f *Fit) []int {
	order := make([]int, len(s.Rowers))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		x, y := order[a], order[b]
		if f.Skill[x] != f.Skill[y] {
			return f.Skill[x] > f.Skill[y]
		}
		return s.Rowers[x].Name < s.Rowers[y].Name
	})
	return order
}

// Select picks the boat from a set of speeds: the fastest `Seats` rowers for sculling, or for a
// sweep boat the fastest half on each side, with either-side rowers filling whichever side gains
// most. Exact: the either-siders used are always the fastest ones, so only how many go to each
// side needs searching.
func Select(s *Session, speed []float64) []bool {
	in := make([]bool, len(s.Rowers))
	byDesc := func(ids []int) {
		sort.SliceStable(ids, func(a, b int) bool { return speed[ids[a]] > speed[ids[b]] })
	}
	if !s.Sweep {
		ids := make([]int, len(s.Rowers))
		for i := range ids {
			ids[i] = i
		}
		byDesc(ids)
		for _, i := range ids[:s.Seats] {
			in[i] = true
		}
		return in
	}
	var bow, stroke, either []int
	for i, r := range s.Rowers {
		switch r.Side {
		case Bow:
			bow = append(bow, i)
		case Stroke:
			stroke = append(stroke, i)
		default:
			either = append(either, i)
		}
	}
	byDesc(bow)
	byDesc(stroke)
	byDesc(either)
	sum := func(ids []int, n int) float64 {
		t := 0.0
		for _, i := range ids[:n] {
			t += speed[i]
		}
		return t
	}
	half := s.Seats / 2
	bestX, bestY, best := -1, -1, math.Inf(-1)
	for x := 0; x <= half; x++ { // either-siders rowing bow side
		for y := 0; y <= half; y++ { // and stroke side
			if half-x > len(bow) || half-y > len(stroke) || x+y > len(either) {
				continue
			}
			if t := sum(bow, half-x) + sum(stroke, half-y) + sum(either, x+y); t > best {
				bestX, bestY, best = x, y, t
			}
		}
	}
	if bestX < 0 {
		return in // no boat can be filled (Parse rules this out)
	}
	for _, i := range bow[:half-bestX] {
		in[i] = true
	}
	for _, i := range stroke[:half-bestY] {
		in[i] = true
	}
	for _, i := range either[:bestX+bestY] {
		in[i] = true
	}
	return in
}

// Chances estimates each rower's probability of making the boat, by drawing many plausible sets
// of speeds from the fit's uncertainty and selecting from each (a fixed seed keeps it repeatable).
func Chances(s *Session, f *Fit, draws int) ([]float64, error) {
	R := f.r
	sub := newMatrix(R, R)
	for i := 0; i < R; i++ {
		copy(sub[i], f.cov[i][:R])
	}
	l, err := cholesky(sub)
	if err != nil {
		return nil, err
	}
	rng := rand.New(rand.NewPCG(2026, 1026))
	z := make([]float64, R)
	speed := make([]float64, R)
	count := make([]float64, R)
	for d := 0; d < draws; d++ {
		for i := range z {
			z[i] = rng.NormFloat64()
		}
		for i := 0; i < R; i++ {
			v := f.mean[i]
			for k := 0; k <= i; k++ {
				v += l[i][k] * z[k]
			}
			speed[i] = v
		}
		for i, in := range Select(s, speed) {
			if in {
				count[i]++
			}
		}
	}
	for i := range count {
		count[i] /= float64(draws)
	}
	return count, nil
}

// Pair is a comparison across the selection line: In is ranked inside the boat, Out just outside.
type Pair struct {
	In, Out int
	Wrong   float64 // probability that Out is really the faster of the two
}

func misorder(diff, sd float64) float64 {
	if sd <= 0 {
		return 0
	}
	return normalCDF(-diff / sd)
}

// CutPairs lists every pair of a rower in the boat and one outside it who could take their seat
// (same side, or either-side), most doubtful first.
func CutPairs(s *Session, f *Fit) []Pair {
	in := Select(s, f.mean[:f.r])
	var pairs []Pair
	for i := range s.Rowers {
		for j := range s.Rowers {
			if !in[i] || in[j] || !CanSwap(s.Rowers[i].Side, s.Rowers[j].Side) {
				continue
			}
			diff := f.mean[i] - f.mean[j]
			pairs = append(pairs, Pair{In: i, Out: j, Wrong: misorder(diff, f.DiffSD(i, j))})
		}
	}
	sort.SliceStable(pairs, func(a, b int) bool { return pairs[a].Wrong > pairs[b].Wrong })
	return pairs
}

func expectedWrong(pairs []Pair) float64 {
	total := 0.0
	for _, p := range pairs {
		total += p.Wrong
	}
	return total
}

// Swap is a suggestion for the next piece: trade A (from boat 1 of the last piece) with B (from
// boat 2). A and B are -1 for "race the same crews again".
type Swap struct {
	A, B          int
	HullA, HullB  string
	Before, After float64 // expected number of wrong calls across the selection line
}

// NextSwaps scores every allowed one-for-one swap between the first two boats of the last piece:
// how much would one more piece with that swap settle the selection? It assumes the estimates
// stay put and only their uncertainty shrinks, which is the usual way to plan an experiment.
func NextSwaps(s *Session, f *Fit) []Swap {
	last := s.Pieces[len(s.Pieces)-1]
	b0, b1 := last.Boats[0], last.Boats[1]
	hull := map[string]int{}
	for i, h := range s.Hulls {
		hull[h] = i
	}
	pairs := CutPairs(s, f)
	before := expectedWrong(pairs)

	score := func(crew0, crew1 []int) float64 {
		u := newUpdate(f, marginVector(f, crew0, crew1, hull[b0.Hull], hull[b1.Hull]))
		total := 0.0
		for _, p := range pairs {
			sd := math.Sqrt(u.diffVar(p.In, p.Out))
			total += misorder(f.mean[p.In]-f.mean[p.Out], sd)
		}
		return total
	}

	swaps := []Swap{{A: -1, B: -1, HullA: b0.Hull, HullB: b1.Hull, Before: before, After: score(b0.Crew, b1.Crew)}}
	for ia, a := range b0.Crew {
		for ib, b := range b1.Crew {
			if !CanSwap(s.Rowers[a].Side, s.Rowers[b].Side) {
				continue
			}
			c0 := append([]int(nil), b0.Crew...)
			c1 := append([]int(nil), b1.Crew...)
			c0[ia], c1[ib] = b, a
			swaps = append(swaps, Swap{A: a, B: b, HullA: b0.Hull, HullB: b1.Hull, Before: before, After: score(c0, c1)})
		}
	}
	sort.SliceStable(swaps, func(i, j int) bool { return swaps[i].After < swaps[j].After })
	return swaps
}

// marginVector is how one more margin between two crews depends on the speeds and hull effects:
// (time of crew 0) - (time of crew 1) = d . (speeds, hulls) + noise.
func marginVector(f *Fit, crew0, crew1 []int, hull0, hull1 int) []float64 {
	d := make([]float64, f.r+f.h)
	for _, r := range crew0 {
		d[r]--
	}
	for _, r := range crew1 {
		d[r]++
	}
	d[f.r+hull0]++
	d[f.r+hull1]--
	return d
}

// update describes the fit after one more piece with margin vector d. The new piece's own level
// cancels in the margin, which then has noise variance 2 sigma^2, so the covariance updates by
// the Sherman-Morrison formula instead of a refit:
// cov' = cov - (cov d)(cov d)^T / (2 sigma^2 + d^T cov d).
type update struct {
	f     *Fit
	cd    []float64
	denom float64
}

func newUpdate(f *Fit, d []float64) update {
	cd := mulVec(f.cov, d)
	return update{f: f, cd: cd, denom: 2*f.Sigma*f.Sigma + dot(d, cd)}
}

// diffVar is Var(speed i - speed j) after the piece.
func (u update) diffVar(i, j int) float64 {
	c := u.f.cov
	v := c[i][i] + c[j][j] - 2*c[i][j] - (u.cd[i]-u.cd[j])*(u.cd[i]-u.cd[j])/u.denom
	return math.Max(v, 0)
}

func dot(a, b []float64) float64 {
	t := 0.0
	for i := range a {
		t += a[i] * b[i]
	}
	return t
}
