package setlist

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

var bars = []rune(" ▁▂▃▄▅▆▇█")

// bar draws a value from 0 to 5 as one block character.
func bar(v float64) string {
	i := int(v/5*float64(len(bars)-1) + 0.5)
	if i < 0 {
		i = 0
	}
	if i >= len(bars) {
		i = len(bars) - 1
	}
	return string(bars[i])
}

func pad(s string, width int) string {
	if n := utf8.RuneCountInString(s); n < width {
		return s + strings.Repeat(" ", width-n)
	}
	return s
}

// Render prints the running order the way a band would tape it to the floor, plus the
// reasoning: what was left out, where time goes, and how the energy flows.
func Render(g *Gig, p *Plan, name string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "SETSMITH  %s  (slot %s, %d of %d songs)\n\n", name, FormatClock(g.Slot), len(p.Order), len(g.Songs))
	width := 4
	for _, s := range p.Order {
		width = max(width, utf8.RuneCountInString(g.Songs[s].Title))
	}
	fmt.Fprintf(&b, " #  Start  %s  Length  Energy\n", pad("Song", width))
	clock := 0
	for k, s := range p.Order {
		song := g.Songs[s]
		if k > 0 {
			c := p.Changes[k]
			clock += g.Gap + c.Secs
			if len(c.Notes) > 0 {
				fmt.Fprintf(&b, "           ↳ %s (%s): a good moment to talk to the crowd\n",
					strings.Join(c.Notes, "; "), FormatClock(c.Secs))
			} else if g.Songs[p.Order[k-1]].Then == song.Title {
				fmt.Fprintf(&b, "           ↳ straight into it\n")
			}
		}
		marks := ""
		if song.Hard {
			marks = "  (hard on the voice)"
		}
		fmt.Fprintf(&b, "%2d  %5s  %s  %6s  %s%s\n", k+1, FormatClock(clock), pad(song.Title, width),
			FormatClock(song.Secs), strings.Repeat("█", song.Energy)+strings.Repeat("·", 5-song.Energy), marks)
		clock += song.Secs
	}
	spare := g.Slot - p.Total
	fmt.Fprintf(&b, "\nLast note at %s of %s: %s for talking, encores and surprises.\n",
		FormatClock(p.Total), FormatClock(g.Slot), FormatClock(spare))
	if spare < 0 {
		fmt.Fprintf(&b, "Warning: this runs over the slot. Cut the reserve's talking short, or make a song a maybe.\n")
	}

	if len(p.Left) > 0 {
		b.WriteString("\nLEFT OUT\n")
		for _, s := range p.Left {
			why := "it didn't fit the time"
			if g.Songs[s].Priority == Maybe {
				why = "a maybe, and the set is better without it"
			}
			fmt.Fprintf(&b, "  %s (%s): %s\n", g.Songs[s].Title, g.Songs[s].Priority, why)
		}
	}

	var arc, ideal strings.Builder
	music := 0
	for _, s := range p.Order {
		arc.WriteString(bar(float64(g.Songs[s].Energy)))
		ideal.WriteString(bar(TargetEnergy((float64(music) + float64(g.Songs[s].Secs)/2) / float64(p.Budget))))
		music += g.Songs[s].Secs
	}
	retunes := 0
	for _, c := range p.Changes {
		if c.Secs > 0 {
			retunes++
		}
	}
	fmt.Fprintf(&b, "\nENERGY  %s   (the ideal shape: %s)\n", arc.String(), ideal.String())
	fmt.Fprintf(&b, "CHANGES %d, costing %s on stage\n", retunes, FormatClock(p.ChangeSecs))
	fmt.Fprintf(&b, "SCORE   %.0f  (= %d s of changes + %.0f energy + %.0f for songs left out; lower is better)\n",
		p.Score, p.ChangeSecs, p.EnergyCost, p.DropCost)
	return b.String()
}
