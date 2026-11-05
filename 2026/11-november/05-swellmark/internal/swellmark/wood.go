// Package swellmark checks a piece of furniture for joints that seasonal wood movement will break.
package swellmark

// How much wood swells and shrinks as the air around it gets damper and drier.

// Species gives a wood's dimensional change coefficients: the fraction its size changes for each
// 1 % change in moisture content, across the growth rings (radial) and along them (tangential).
type Species struct {
	Name       string
	Radial     float64
	Tangential float64
}

// Longitudinal is the change along the grain, which is tiny: about a fiftieth of the change across it.
const Longitudinal = 0.00005

// Approximate coefficients for common furniture woods, after the USDA Forest Products Laboratory's
// Wood Handbook (valid for moisture contents of about 6 to 14 %). A design can add or override
// species with a `species` line.
var builtinSpecies = []Species{
	{"ash", 0.00169, 0.00274},
	{"beech", 0.00190, 0.00431},
	{"birch", 0.00256, 0.00338},
	{"cherry", 0.00126, 0.00248},
	{"douglas-fir", 0.00165, 0.00267},
	{"maple", 0.00165, 0.00353},
	{"pine", 0.00071, 0.00212},
	{"poplar", 0.00158, 0.00289},
	{"red-oak", 0.00158, 0.00369},
	{"teak", 0.00101, 0.00186},
	{"walnut", 0.00190, 0.00274},
	{"white-oak", 0.00180, 0.00365},
}

// EMC is the moisture content (% of dry weight) that wood settles at in air of the given relative
// humidity (%) and temperature (°C): the Hailwood–Horrobin sorption model, with the constants
// fitted to wood in the Wood Handbook.
func EMC(rh, tempC float64) float64 {
	h := rh / 100
	t := tempC
	w := 349 + 1.29*t + 0.0135*t*t
	k := 0.805 + 0.000736*t - 0.00000273*t*t
	k1 := 6.27 - 0.00938*t - 0.000303*t*t
	k2 := 1.91 + 0.0407*t - 0.000293*t*t
	kh := k * h
	return 1800 / w * (kh/(1-kh) + (k1*kh+2*k1*k2*kh*kh)/(1+k1*kh+k1*k2*kh*kh))
}

// Cut is how a board was sawn from the log, which decides which face moves most.
type Cut int

const (
	// Flat (plain) sawn: the rings run across the board's width, so its width moves tangentially.
	Flat Cut = iota
	// Quarter sawn: the rings run through the thickness, so its width moves radially (least).
	Quarter
	// Rift sawn: rings at about 45°, between the two.
	Rift
)

var cutNames = map[string]Cut{"flat": Flat, "quarter": Quarter, "rift": Rift}

// Coefficient is how much a part changes size along a direction of the piece, per 1 % moisture.
func (p *Part) Coefficient(axis byte) float64 {
	tang, rad := p.Species.Tangential, p.Species.Radial
	switch {
	case axis == p.Grain:
		return Longitudinal
	case p.Cut == Rift:
		return (tang + rad) / 2
	case (axis == p.Width) == (p.Cut == Flat):
		return tang // the width of a flat-sawn board, or the thickness of a quarter-sawn one
	default:
		return rad
	}
}
