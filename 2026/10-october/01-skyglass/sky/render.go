package sky

import (
	"math"
	"strings"
)

// RenderMoon draws the Moon as ASCII art with the given radius in text rows.
//
// For each row we know how wide the disc is (w). The terminator, the line
// between day and night on the Moon, sits at x = w·cos(2π·phase). While the
// Moon waxes, everything to the right of it is lit; while it wanes, the lit
// part is on the left. From the southern hemisphere the Moon looks flipped
// left-to-right, so southern viewers get a mirrored drawing.
func RenderMoon(phase float64, radius int, southern bool) string {
	const lit, dark = '#', '.'
	var b strings.Builder
	r := float64(radius)
	for row := -radius; row <= radius; row++ {
		// Shrink y slightly so the top and bottom rows aren't a single dot.
		y := float64(row) * r / (r + 0.5)
		w := math.Sqrt(math.Max(r*r-y*y, 0))
		xt := w * math.Cos(2*math.Pi*phase)
		// Characters are about twice as tall as wide, so use two columns per unit.
		for col := -2 * radius; col <= 2*radius; col++ {
			x := float64(col) / 2
			if math.Abs(x) > w {
				b.WriteByte(' ')
				continue
			}
			vx := x
			if southern {
				vx = -x
			}
			var on bool
			if phase < 0.5 {
				on = vx > xt
			} else {
				on = vx <= -xt // <= so the rim is lit at exactly full moon
			}
			if on {
				b.WriteRune(lit)
			} else {
				b.WriteRune(dark)
			}
		}
		b.WriteString("\n")
	}
	// Trim trailing spaces so the output is tidy.
	lines := strings.Split(strings.TrimRight(b.String(), "\n"), "\n")
	for i, l := range lines {
		lines[i] = strings.TrimRight(l, " ")
	}
	return strings.Join(lines, "\n")
}
