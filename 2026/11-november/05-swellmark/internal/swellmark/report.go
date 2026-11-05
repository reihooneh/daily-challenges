package swellmark

import (
	"fmt"
	"math"
	"strings"
)

// roundUpHalf rounds a size up to the next half millimetre, for advice someone will cut to.
func roundUpHalf(mm float64) float64 { return math.Ceil(mm*2-1e-9) / 2 }

// nouns name each fastening in a sentence.
var nouns = map[string]string{
	"glue": "Glue", "screws": "Screws", "pegs": "Pegs", "nails": "Nails",
	"slots": "Slots", "buttons": "Buttons", "figure8": "Figure-8 fasteners",
}

// mm shows a signed movement, without a "-0.00".
func mm(v float64) string {
	if math.Abs(v) < 0.005 {
		v = 0
	}
	return fmt.Sprintf("%+.2f", v)
}

func season(damp bool) string {
	if damp {
		return "damp"
	}
	return "dry"
}

func fastening(j *Joint) string {
	switch j.Kind {
	case Sliding:
		return fmt.Sprintf("%s %g", j.Fastening, j.Allow)
	case Floating:
		return fmt.Sprintf("floating %g/%g", j.Allow, j.Depth)
	}
	return j.Fastening
}

func allows(d *Design, j *Joint) string {
	switch j.Kind {
	case Sliding:
		return fmt.Sprintf("%g mm each way", j.Allow)
	case Floating:
		return fmt.Sprintf("%g mm gap", j.Allow)
	}
	return fmt.Sprintf("%.2g mm (rigid)", d.RigidLimit)
}

// advice says what goes wrong and what to change, in the shop's terms.
func advice(d *Design, r Result) string {
	j := r.Joint
	moves := fmt.Sprintf("the parts move %.2f mm against each other in the %s season", r.Need, season(r.Damper))
	switch j.Kind {
	case Rigid:
		what := "may crack or open a little"
		if r.Verdict == Fail {
			what = "will crack or tear apart"
		}
		return fmt.Sprintf("%s can't slide, so the joint %s: %s. Fix it at the middle only and let the rest slide (slots or elongated holes of at least %.1f mm each way).",
			nouns[j.Fastening], what, moves, roundUpHalf(r.Need))
	case Sliding:
		what := "have little travel to spare"
		if r.Verdict == Fail {
			what = "run out of travel and will bind or split"
		}
		return fmt.Sprintf("The %s %s: %s. Allow at least %.1f mm each way.", strings.ToLower(nouns[j.Fastening]), what, moves, roundUpHalf(r.Need*1.25))
	}
	shrink := math.Max(0, math.Max(-r.Damp, -r.Dry))
	if r.Need > j.Allow*0.75 {
		what := "nearly fills its gap"
		if r.Need > j.Allow {
			what = "swells past its gap and will push the frame apart"
		}
		return fmt.Sprintf("The panel %s in the damp season (it grows %.2f mm). Leave a gap of at least %.1f mm in all when building at %g %% humidity.",
			what, r.Need, roundUpHalf(r.Need/0.75), d.Built)
	}
	what := "stays only just in its grooves"
	if r.Engaged < MinEngagement {
		what = "can shrink out of its grooves"
	}
	return fmt.Sprintf("The panel %s in the dry season (%.1f mm left on each side after shrinking %.2f mm). Make the grooves at least %.1f mm deep.",
		what, math.Max(0, r.Engaged), shrink, roundUpHalf(1.5*MinEngagement+j.Allow/2+shrink/2))
}

func ranges(rs []Range) string {
	var parts []string
	for _, r := range rs {
		if r.From == r.To {
			parts = append(parts, fmt.Sprintf("%d %%", r.From))
		} else {
			parts = append(parts, fmt.Sprintf("%d–%d %%", r.From, r.To))
		}
	}
	return strings.Join(parts, " or ")
}

// Render is the full report.
func Render(d *Design) string {
	var b strings.Builder
	m := MoistureAt(d, d.Built)
	results := Check(d)
	fmt.Fprintf(&b, "SWELLMARK  %s\n", d.Title)
	fmt.Fprintf(&b, "Indoor humidity over the year: %g %% to %g %% at %g °C, so the wood's moisture runs from %.1f %% to %.1f %%.\n",
		d.Low, d.High, d.TempC, m.Low, m.High)
	fmt.Fprintf(&b, "Built at %g %% humidity (%.1f %% moisture).\n\n", d.Built, m.Built)

	names := make([]string, len(results))
	width := len("Joint")
	for i, r := range results {
		names[i] = r.Joint.A.Name + " + " + r.Joint.B.Name
		width = max(width, len(names[i]))
	}
	fmt.Fprintf(&b, "  %-7s  %-*s  %-14s  %-10s  %-20s  %s\n", "Verdict", width, "Joint", "Fastening", "Along", "Moves (damp / dry)", "Allows")
	counts := [3]int{}
	for i, r := range results {
		j := r.Joint
		counts[r.Verdict]++
		fmt.Fprintf(&b, "  %-7s  %-*s  %-14s  %-10s  %-20s  %s\n", r.Verdict, width, names[i], fastening(j),
			fmt.Sprintf("%c %g mm", j.Axis, j.Extent), mm(r.Damp)+" / "+mm(r.Dry)+" mm", allows(d, j))
	}

	if counts[Fail]+counts[Watch] > 0 {
		b.WriteString("\nWhat to change:\n")
		for _, want := range []Verdict{Fail, Watch} {
			for i, r := range results {
				if r.Verdict == want {
					fmt.Fprintf(&b, "  %-5s %s (line %d): %s\n", r.Verdict, names[i], r.Joint.Line, advice(d, r))
				}
			}
		}
	}

	fmt.Fprintf(&b, "\nIn all: %d OK, %d to watch, %d failing.\n", counts[OK], counts[Watch], counts[Fail])
	safe, comfortable := BuildWindows(d)
	switch {
	case len(safe) == 0:
		b.WriteString("No shop humidity from 10 % to 90 % saves every joint: the design itself has to change.\n")
	case len(comfortable) == 0:
		fmt.Fprintf(&b, "Building at %s humidity keeps every joint from failing, but none is comfortable at any humidity.\n", ranges(safe))
	default:
		fmt.Fprintf(&b, "Building at %s humidity keeps every joint from failing; %s keeps every joint OK.\n", ranges(safe), ranges(comfortable))
	}
	return b.String()
}
