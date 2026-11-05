package swellmark

import "math"

// Verdict is what a joint will do over a year.
type Verdict int

const (
	OK Verdict = iota
	Watch
	Fail
)

func (v Verdict) String() string {
	return [...]string{"OK", "WATCH", "FAIL"}[v]
}

// MinEngagement is the least a panel should stay in its groove (mm) at its driest.
const MinEngagement = 3.0

// Result is one joint over the year.
type Result struct {
	Joint   *Joint
	Damp    float64 // A's movement relative to B at the dampest time (mm; + means A grew more)
	Dry     float64 // the same at the driest time
	Need    float64 // rigid and sliding: the most the joint must absorb; floating: the gap needed
	Engaged float64 // floating: how much of the panel is left in each groove at its driest
	Verdict Verdict
	Damper  bool // the worst of it comes in the damp season (otherwise the dry)
}

// Moisture is the wood's moisture content at the build humidity and the year's extremes.
type Moisture struct{ Built, Low, High float64 }

// MoistureAt gives the moisture contents for a design built at a given humidity.
func MoistureAt(d *Design, builtRH float64) Moisture {
	return Moisture{Built: EMC(builtRH, d.TempC), Low: EMC(d.Low, d.TempC), High: EMC(d.High, d.TempC)}
}

// CheckJoint works out how far the two parts of a joint try to move against each other.
//
// Each part changes size along the joint by length × coefficient × change in moisture. Where the
// two coefficients differ (a board's width glued across another's length, say) the joint has to
// absorb the difference. Joints are taken as fixed at their middle, so the ends move by half the
// length's difference, unless the joint is fixed at one end.
func CheckJoint(d *Design, j *Joint, m Moisture) Result {
	dc := j.A.Coefficient(j.Axis) - j.B.Coefficient(j.Axis)
	length := j.Extent / 2
	if j.FromEnd || j.Kind == Floating {
		length = j.Extent
	}
	r := Result{Joint: j, Damp: dc * length * (m.High - m.Built), Dry: dc * length * (m.Low - m.Built)}
	switch j.Kind {
	case Rigid, Sliding:
		r.Need = math.Max(math.Abs(r.Damp), math.Abs(r.Dry))
		r.Damper = math.Abs(r.Damp) >= math.Abs(r.Dry)
		limit := d.RigidLimit
		watch := limit
		fail := 2 * limit
		if j.Kind == Sliding {
			watch, fail = 0.75*j.Allow, j.Allow
		}
		switch {
		case r.Need > fail+1e-9:
			r.Verdict = Fail
		case r.Need > watch+1e-9:
			r.Verdict = Watch
		}
	case Floating:
		grow := math.Max(0, math.Max(r.Damp, r.Dry))
		shrink := math.Max(0, math.Max(-r.Damp, -r.Dry))
		r.Need = grow
		r.Engaged = j.Depth - j.Allow/2 - shrink/2
		tooBig := grow > j.Allow+1e-9
		pulledOut := r.Engaged < MinEngagement-1e-9
		r.Damper = tooBig || !pulledOut && grow >= shrink
		switch {
		case tooBig || pulledOut:
			r.Verdict = Fail
		case grow > 0.75*j.Allow+1e-9 || r.Engaged < 1.5*MinEngagement-1e-9:
			r.Verdict = Watch
		}
	}
	return r
}

// Check works out every joint for the design as built.
func Check(d *Design) []Result {
	m := MoistureAt(d, d.Built)
	out := make([]Result, len(d.Joints))
	for i := range d.Joints {
		out[i] = CheckJoint(d, &d.Joints[i], m)
	}
	return out
}

// Range is a span of build humidities (%), inclusive.
type Range struct{ From, To int }

// BuildWindows tries building the same design at every whole humidity from 10 % to 90 % and gives
// the spans where no joint fails (safe) and where every joint is OK (comfortable).
func BuildWindows(d *Design) (safe, comfortable []Range) {
	add := func(rs []Range, rh int) []Range {
		if n := len(rs); n > 0 && rs[n-1].To == rh-1 {
			rs[n-1].To = rh
			return rs
		}
		return append(rs, Range{rh, rh})
	}
	for rh := 10; rh <= 90; rh++ {
		m := MoistureAt(d, float64(rh))
		worst := OK
		for i := range d.Joints {
			if v := CheckJoint(d, &d.Joints[i], m).Verdict; v > worst {
				worst = v
			}
		}
		if worst != Fail {
			safe = add(safe, rh)
		}
		if worst == OK {
			comfortable = add(comfortable, rh)
		}
	}
	return safe, comfortable
}
