// Command ovenslot plans a meal in one oven: ovenslot MEAL.json
package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"ovenslot/ovenslot"
)

func report(w io.Writer, m *ovenslot.Meal, p ovenslot.Plan, complete bool) {
	fmt.Fprintf(w, "%d dishes, %g shelves, served at %s: %d temperature%s, oven on for %d min.\n\n", len(m.Dishes), m.Shelves,
		m.Serve, len(p.Phases), map[bool]string{true: "", false: "s"}[len(p.Phases) == 1], int(p.On+0.5))
	type event struct {
		at   float64
		text string
		ord  int // order at the same minute
	}
	var ev []event
	first := p.Phases[0]
	pre := (first.Temp - ovenslot.Room) / ovenslot.HeatRate
	ev = append(ev, event{first.Start - pre, fmt.Sprintf("Turn the oven on to %g °C", first.Temp), 1})
	for i := 1; i < len(p.Phases); i++ {
		prev, ph := p.Phases[i-1], p.Phases[i]
		verb := "up"
		if ph.Temp < prev.Temp {
			verb = "down, door ajar"
		}
		ev = append(ev, event{prev.End, fmt.Sprintf("Turn the oven %s to %g °C", verb, ph.Temp), 1})
	}
	for _, s := range p.Slots {
		d := m.Dishes[s.Dish]
		note := ""
		if s.Temp != d.Temp {
			note = fmt.Sprintf(" (at %g °C instead of %g: %d min)", s.Temp, d.Temp, int(d.TimeAt(s.Temp)+0.5))
		}
		ev = append(ev, event{s.In, fmt.Sprintf("%s in%s", d.Name, note), 2})
		wait := m.ServeAt() - s.Out
		out := fmt.Sprintf("%s out (%d min before serving)", d.Name, int(wait+0.5))
		if wait < 0.5 {
			out = d.Name + " out, straight to the table"
		}
		ev = append(ev, event{s.Out, out, 0})
	}
	ev = append(ev, event{p.Phases[len(p.Phases)-1].End, "Oven off", 3})
	ev = append(ev, event{m.ServeAt(), "Serve", 4})
	sort.SliceStable(ev, func(a, b int) bool {
		if ev[a].at != ev[b].at {
			return ev[a].at < ev[b].at
		}
		return ev[a].ord < ev[b].ord // things come out before the dial turns, which is before things go in
	})
	for _, e := range ev {
		fmt.Fprintf(w, "  %s  %s\n", ovenslot.Clock(e.at), e.text)
	}
	if !complete {
		fmt.Fprintln(w, "\n(The search stopped at its limit: a plan with fewer changes may exist.)")
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: ovenslot MEAL.json")
		os.Exit(2)
	}
	info, err := os.Lstat(os.Args[1])
	if err != nil || !info.Mode().IsRegular() || info.Size() > ovenslot.MaxBytes {
		fmt.Fprintln(os.Stderr, "ovenslot: the meal must be a regular file under 32 KB")
		os.Exit(2)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, "ovenslot: can't read the file")
		os.Exit(2)
	}
	m, err := ovenslot.Parse(data)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ovenslot:", err)
		os.Exit(2)
	}
	plan, found, complete := ovenslot.Best(m)
	if !found {
		var names []string
		for _, d := range m.Dishes {
			names = append(names, d.Name)
		}
		fmt.Printf("No plan fits %s into one oven by %s with %g shelves. Cook something ahead, or on the stove.\n",
			strings.Join(names, ", "), m.Serve, m.Shelves)
		os.Exit(1)
	}
	report(os.Stdout, m, plan, complete)
}
