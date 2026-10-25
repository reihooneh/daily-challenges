package bowball

import (
	"fmt"
	"math"
	"sort"
	"strings"
)

// Draws is how many simulated sets of speeds Render uses for the selection chances.
const Draws = 20000

// Render runs the whole analysis and returns the printed report.
func Render(s *Session) (string, error) {
	f, err := Estimate(s)
	if err != nil {
		return "", fmt.Errorf("the results could not be fitted")
	}
	chance, err := Chances(s, f, Draws)
	if err != nil {
		return "", fmt.Errorf("the results could not be fitted")
	}
	var b strings.Builder
	w := func(format string, args ...any) { fmt.Fprintf(&b, format, args...) }

	w("BOWBALL  %s\n", s.Name)
	w("%d rowers, %d pieces, %d seats to fill.\n", len(s.Rowers), len(s.Pieces), s.Seats)
	w("Speed: seconds per 1000 m a rower takes off a crew, compared with the average of their side.\n")
	if f.FromData {
		w("Timing noise: about %.2f s per 1000 m per crew, estimated from the results.\n\n", f.Sigma)
	} else {
		w("Timing noise: assumed about %.2f s per 1000 m per crew (too few pieces to estimate it yet).\n\n", f.Sigma)
	}

	chosen := Select(s, f.mean[:len(s.Rowers)])
	for _, group := range sideGroups(s) {
		title := "SQUAD"
		if s.Sweep {
			title = strings.ToUpper(s.Rowers[group[0]].Side.String()) + " SIDE"
			if s.Rowers[group[0]].Side == Either {
				title = "EITHER SIDE"
			}
		}
		sort.SliceStable(group, func(a, b int) bool { return f.Skill[group[a]] > f.Skill[group[b]] })
		w("%-22s %8s %6s   %-6s %s\n", title, "Speed", "+/-", "Boat", "Chance of a seat")
		for rank, i := range group {
			speed, se := fmt.Sprintf("%+.2f", f.Skill[i]), fmt.Sprintf("%.2f", f.SE[i])
			if !f.Separated(i) {
				speed, se = "?", "?"
			}
			mark := ""
			if chosen[i] {
				mark = "in"
			}
			verdict := fmt.Sprintf("%3.0f%%  %s", chance[i]*100, bar(chance[i]))
			if !f.Separated(i) {
				verdict += "  (not compared yet: needs a swap)"
			}
			w("  %-20s %8s %6s   %-6s %s\n", fmt.Sprintf("%d. %s", rank+1, s.Rowers[i].Name), speed, se, mark, verdict)
		}
		w("\n")
	}

	if len(s.Hulls) > 1 {
		parts := []string{}
		for k, h := range s.Hulls {
			parts = append(parts, fmt.Sprintf("%s %+.2f (+/- %.2f)", h, f.Hull[k], f.HullSE[k]))
		}
		w("Hulls (seconds per 1000 m slower than average): %s.\n", strings.Join(parts, ", "))
		w("Swapping rowers between hulls is what lets the hull difference be measured and taken out.\n\n")
	}

	pairs := CutPairs(s, f)
	w("Closest calls at the selection line:\n")
	shown := 0
	for _, p := range pairs {
		if shown == 3 || p.Wrong < 0.05 {
			break
		}
		w("  %s over %s: %.0f%% chance that's the wrong way round\n", s.Rowers[p.In].Name, s.Rowers[p.Out].Name, p.Wrong*100)
		shown++
	}
	if shown == 0 {
		w("  none: every rower inside the line is at least 95%% likely to be faster than every rower outside it.\n")
	}
	w("\n")

	swaps := NextSwaps(s, f)
	w("Next piece: start from the last piece's %s and %s crews and\n", swaps[0].HullA, swaps[0].HullB)
	for k, sw := range swaps {
		if k == 3 {
			break
		}
		what := "race the same crews again"
		if sw.A >= 0 {
			what = fmt.Sprintf("swap %s (%s) with %s (%s)", s.Rowers[sw.A].Name, sw.HullA, s.Rowers[sw.B].Name, sw.HullB)
		}
		w("  %d. %-44s expected wrong calls %.2f -> %.2f\n", k+1, what, sw.Before, sw.After)
	}
	w("\n")

	if f.Odd != nil {
		p := s.Pieces[f.Odd.Piece]
		w("Check piece %d (line %d): %s's time is %.1f noise-widths from what the other results predict.\n",
			f.Odd.Piece+1, p.Boats[f.Odd.Boat].Line, p.Boats[f.Odd.Boat].Hull, math.Abs(f.Odd.Residual))
		w("A crab, a steering error or a gust can do that; consider racing it again.\n\n")
	}
	w("Seat racing measures who moves a boat, not technique or attitude: one input to selection, not the whole of it.\n")
	return b.String(), nil
}

func bar(p float64) string {
	n := int(math.Round(p * 10))
	return strings.Repeat("#", n) + strings.Repeat(".", 10-n)
}
