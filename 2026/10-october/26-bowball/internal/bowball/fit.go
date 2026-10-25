package bowball

import "math"

// The model, in seconds per 1000 m. For boat b in piece p:
//
//	time = piece_p + hull_b - sum of the speeds of the rowers in it + noise
//
// The piece term soaks up wind, stream and tiredness, which are the same for every boat in a
// piece, so only differences within a piece matter. A rower's speed is how many seconds per
// 1000 m they take off a crew compared with an average squad member.
//
// Speeds and hull effects get weak normal priors (sd 5 s and 3 s per 1000 m). With enough swaps
// the data swamp them. Until a rower has been swapped, their speed stays uncertain instead of
// the whole calculation breaking, so the "next swap" advice still works on day one.
const (
	priorSpeed = 5.0
	priorHull  = 3.0
	priorDF    = 2.0 // how much the stated noise counts, in pieces' worth of evidence
	// A rower whose speed is still this uncertain hasn't really been compared yet.
	unseparated = 0.4 * priorSpeed
)

// Fit is what the results say.
type Fit struct {
	Skill    []float64 // seconds per 1000 m faster than the squad average (positive = faster)
	SE       []float64 // standard error of Skill
	Hull     []float64 // seconds per 1000 m slower than the average hull
	HullSE   []float64
	Sigma    float64 // timing noise per crew, seconds per 1000 m
	FromData bool    // Sigma was estimated from the results, not just assumed
	SpareDF  float64 // results beyond what the parameters use up
	Odd      *Oddity // the result that fits worst, if it is far out

	cov  matrix    // covariance of the raw speeds then hull effects
	mean []float64 // their estimates
	r, h int
}

// Oddity is a boat time that doesn't fit the rest: a crab, a steering error, a gust.
type Oddity struct {
	Piece, Boat int
	Residual    float64 // in noise standard deviations
}

// Separated reports whether rower i has been compared well enough to rank.
func (f *Fit) Separated(i int) bool { return f.SE[i] < unseparated }

// DiffSD is the standard deviation of Skill[i] - Skill[j].
func (f *Fit) DiffSD(i, j int) float64 {
	if i == j {
		return 0
	}
	c := make([]float64, f.r+f.h)
	c[i], c[j] = 1, -1
	return math.Sqrt(quad(f.cov, c))
}

type observation struct {
	cols  []int
	coefs []float64
	y     float64
	piece int
	boat  int
}

func observations(s *Session) []observation {
	hullIndex := map[string]int{}
	for i, h := range s.Hulls {
		hullIndex[h] = i
	}
	P, R := len(s.Pieces), len(s.Rowers)
	var obs []observation
	for p, piece := range s.Pieces {
		scale := 1000 / piece.Distance
		for b, boat := range piece.Boats {
			o := observation{y: boat.Time * scale, piece: p, boat: b}
			o.cols = append(o.cols, p)
			o.coefs = append(o.coefs, 1)
			for _, r := range boat.Crew {
				o.cols = append(o.cols, P+r)
				o.coefs = append(o.coefs, -1)
			}
			o.cols = append(o.cols, P+R+hullIndex[boat.Hull])
			o.coefs = append(o.coefs, 1)
			obs = append(obs, o)
		}
	}
	return obs
}

// Estimate fits the model by penalised least squares (the posterior mean under the priors),
// re-estimating the noise level a few times.
func Estimate(s *Session) (*Fit, error) { return estimate(s, 0) }

// estimate does the work; a positive fixedSigma holds the noise level fixed (for tests).
func estimate(s *Session, fixedSigma float64) (*Fit, error) {
	P, R, H := len(s.Pieces), len(s.Rowers), len(s.Hulls)
	n := P + R + H
	obs := observations(s)
	xtx := newMatrix(n, n)
	xty := make([]float64, n)
	for _, o := range obs {
		for a, ca := range o.cols {
			xty[ca] += o.coefs[a] * o.y
			for b, cb := range o.cols {
				xtx[ca][cb] += o.coefs[a] * o.coefs[b]
			}
		}
	}
	sigma := s.Noise
	if fixedSigma > 0 {
		sigma = fixedSigma
	}
	var cov matrix
	var beta []float64
	var spare float64
	for iter := 0; iter < 8; iter++ {
		prec := newMatrix(n, n)
		for i := range prec {
			for j := range prec[i] {
				prec[i][j] = xtx[i][j] / (sigma * sigma)
			}
		}
		for i := P; i < P+R; i++ {
			prec[i][i] += 1 / (priorSpeed * priorSpeed)
		}
		for i := P + R; i < n; i++ {
			prec[i][i] += 1 / (priorHull * priorHull)
		}
		var err error
		cov, err = invert(prec)
		if err != nil {
			return nil, err
		}
		rhs := make([]float64, n)
		for i := range rhs {
			rhs[i] = xty[i] / (sigma * sigma)
		}
		beta = mulVec(cov, rhs)
		rss := 0.0
		for _, o := range obs {
			r := o.y
			for a, c := range o.cols {
				r -= o.coefs[a] * beta[c]
			}
			rss += r * r
		}
		// Parameters actually used up by the data: the trace of the hat matrix.
		used := 0.0
		for i := 0; i < n; i++ {
			for k := 0; k < n; k++ {
				used += xtx[i][k] * cov[k][i]
			}
		}
		used /= sigma * sigma
		spare = float64(len(obs)) - used
		next := math.Sqrt((rss + priorDF*s.Noise*s.Noise) / (math.Max(spare, 0) + priorDF))
		if fixedSigma > 0 || math.Abs(next-sigma) < 1e-9 {
			break
		}
		sigma = next
	}

	f := &Fit{Sigma: sigma, FromData: spare >= 2, SpareDF: spare, r: R, h: H}
	f.cov = newMatrix(R+H, R+H)
	f.mean = make([]float64, R+H)
	for i := 0; i < R+H; i++ {
		f.mean[i] = beta[P+i]
		for j := 0; j < R+H; j++ {
			f.cov[i][j] = cov[P+i][P+j]
		}
	}
	// Report speeds relative to the squad's average, and hulls relative to the average hull.
	f.Skill, f.SE = make([]float64, R), make([]float64, R)
	for _, group := range sideGroups(s) {
		relative(f, group, f.Skill, f.SE)
	}
	hulls := make([]int, H)
	for k := range hulls {
		hulls[k] = R + k
	}
	f.Hull, f.HullSE = make([]float64, R+H), make([]float64, R+H)
	relative(f, hulls, f.Hull, f.HullSE)
	f.Hull, f.HullSE = f.Hull[R:], f.HullSE[R:]

	for _, o := range obs {
		r := o.y
		for a, c := range o.cols {
			r -= o.coefs[a] * beta[c]
		}
		z := r / sigma
		if math.Abs(z) > 3 && (f.Odd == nil || math.Abs(z) > math.Abs(f.Odd.Residual)) {
			f.Odd = &Oddity{Piece: o.piece, Boat: o.boat, Residual: z}
		}
	}
	return f, nil
}

// sideGroups splits the rowers by side. Speeds are only compared within a side: seat racing
// swaps bow-siders with bow-siders, so it never measures bow side against stroke side.
func sideGroups(s *Session) [][]int {
	bySide := map[Side][]int{}
	for i, r := range s.Rowers {
		bySide[r.Side] = append(bySide[r.Side], i)
	}
	var groups [][]int
	for _, side := range []Side{Bow, Stroke, Either} {
		if len(bySide[side]) > 0 {
			groups = append(groups, bySide[side])
		}
	}
	return groups
}

// relative writes each member's estimate relative to the group's average, with its standard error.
func relative(f *Fit, group []int, value, se []float64) {
	avg := 0.0
	for _, i := range group {
		avg += f.mean[i] / float64(len(group))
	}
	for _, i := range group {
		value[i] = f.mean[i] - avg
		c := make([]float64, len(f.mean))
		for _, k := range group {
			c[k] = -1 / float64(len(group))
		}
		c[i]++
		se[i] = math.Sqrt(quad(f.cov, c))
	}
}
