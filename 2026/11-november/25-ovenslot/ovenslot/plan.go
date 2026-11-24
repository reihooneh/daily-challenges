// Package ovenslot plans a meal in one oven: which dishes share a temperature, when each goes in and
// comes out, and when to change the dial, so everything is ready (and rested) at serving time.
package ovenslot

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strconv"
)

const (
	MaxBytes  = 32 * 1024
	MaxDishes = 10
	MaxPhases = 4
	HeatRate  = 10.0 // °C per minute the oven heats
	CoolRate  = 4.0  // °C per minute it cools with the door ajar
	Room      = 20.0
)

var nameRE = regexp.MustCompile(`^[\p{L}\p{N} .,'&()-]{1,40}$`)
var clockRE = regexp.MustCompile(`^([01]\d|2[0-3]):([0-5]\d)$`)

// Dish is one thing to cook.
type Dish struct {
	Name    string  `json:"name"`
	Temp    float64 `json:"temp"`    // the recipe's temperature, °C
	Minutes float64 `json:"minutes"` // at that temperature
	Low     float64 `json:"low"`     // the coolest it can be cooked at
	High    float64 `json:"high"`    // the hottest
	Space   float64 `json:"space"`   // how much of a shelf it takes (1 = a whole shelf)
	RestMin float64 `json:"restMin"` // minutes it must rest before serving
	RestMax float64 `json:"restMax"` // minutes it can wait before it spoils
}

// Meal is the whole job.
type Meal struct {
	Serve   string  `json:"serve"`
	Shelves float64 `json:"shelves"`
	Dishes  []Dish  `json:"dishes"`
	serveAt float64 // minutes after midnight
}

// TimeAt is how long a dish takes at another temperature: cooking time scales with
// 1 / (T - 100 °C), a rule of thumb for roasting and baking above the boiling point.
func (d Dish) TimeAt(t float64) float64 { return d.Minutes * (d.Temp - 100) / (t - 100) }

func bad(format string, args ...any) error { return fmt.Errorf(format, args...) }

func inRange(v, lo, hi float64) bool {
	return !math.IsNaN(v) && !math.IsInf(v, 0) && v >= lo && v <= hi
}

// Parse reads and checks a meal.
func Parse(data []byte) (*Meal, error) {
	if len(data) > MaxBytes {
		return nil, errors.New("the file is larger than 32 KB")
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var m Meal
	if err := dec.Decode(&m); err != nil {
		return nil, errors.New("the file isn't a meal in JSON (check the field names)")
	}
	if dec.More() {
		return nil, errors.New("the file has more than one JSON value")
	}
	c := clockRE.FindStringSubmatch(m.Serve)
	if c == nil {
		return nil, errors.New("serve must be a time like 18:30")
	}
	h, _ := strconv.Atoi(c[1])
	mm, _ := strconv.Atoi(c[2])
	m.serveAt = float64(h*60 + mm)
	if !inRange(m.Shelves, 1, 4) {
		return nil, errors.New("shelves must be 1 to 4")
	}
	if len(m.Dishes) == 0 || len(m.Dishes) > MaxDishes {
		return nil, bad("list 1 to %d dishes", MaxDishes)
	}
	seen := map[string]bool{}
	for i := range m.Dishes {
		d := &m.Dishes[i]
		if !nameRE.MatchString(d.Name) {
			return nil, bad("dish %d needs a short name", i+1)
		}
		if seen[d.Name] {
			return nil, bad("two dishes are called %s", d.Name)
		}
		seen[d.Name] = true
		if d.Low == 0 {
			d.Low = d.Temp
		}
		if d.High == 0 {
			d.High = d.Temp
		}
		switch {
		case !inRange(d.Temp, 110, 260) || !inRange(d.Low, 110, 260) || !inRange(d.High, 110, 260):
			return nil, bad("%s: temperatures must be 110 to 260 °C", d.Name)
		case d.Low > d.Temp || d.Temp > d.High:
			return nil, bad("%s: low <= temp <= high", d.Name)
		case !inRange(d.Minutes, 1, 600):
			return nil, bad("%s: minutes must be 1 to 600", d.Name)
		case !inRange(d.Space, 0.1, 1):
			return nil, bad("%s: space must be 0.1 to 1 shelf", d.Name)
		case !inRange(d.RestMin, 0, 720) || !inRange(d.RestMax, d.RestMin, 720):
			return nil, bad("%s: rest must satisfy 0 <= restMin <= restMax <= 720", d.Name)
		}
	}
	return &m, nil
}

// Slot is one dish's place in the plan, in minutes after midnight.
type Slot struct {
	Dish  int
	Temp  float64
	In    float64
	Out   float64
	Phase int
}

// Phase is a stretch of time at one temperature.
type Phase struct {
	Temp       float64
	Start, End float64 // when the oven is at temperature
}

// Plan is a schedule for the meal.
type Plan struct {
	Phases []Phase
	Slots  []Slot
	On     float64 // minutes the oven is on, preheat included
	Wait   float64 // total minutes dishes wait after cooking beyond their minimum rest
}

func transition(from, to float64) float64 {
	if to >= from {
		return (to - from) / HeatRate
	}
	return (from - to) / CoolRate
}

// temps a dish can share: candidate temperatures in 10 °C steps within its range, plus its own.
func candidates(d Dish) []float64 {
	var out []float64
	for t := math.Ceil(d.Low/10) * 10; t <= d.High; t += 10 {
		out = append(out, t)
	}
	if !contains(out, d.Temp) {
		out = append(out, d.Temp)
	}
	sort.Float64s(out)
	return out
}

func contains(s []float64, v float64) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// schedulePhases places dishes backwards from serving: the last phase ends when the last dish must
// come out; each earlier phase ends when the oven must start changing to the next temperature.
// Within a phase, each dish comes out as late as its window and the phase allow, and starts earlier
// when the shelves are full. Returns false if a dish can't fit its window.
func schedulePhases(m *Meal, groups [][]int, temps []float64) (Plan, bool) {
	var plan Plan
	end := math.Inf(1)
	for p := len(groups) - 1; p >= 0; p-- {
		T := temps[p]
		// Latest any dish in this phase may come out.
		var slots []Slot
		latestOut := math.Inf(-1)
		for _, i := range groups[p] {
			d := m.Dishes[i]
			out := math.Min(end, m.serveAt-d.RestMin)
			if out < m.serveAt-d.RestMax-1e-9 {
				return plan, false
			}
			slots = append(slots, Slot{Dish: i, Temp: T, Out: out, In: out - d.TimeAt(T), Phase: p})
			latestOut = math.Max(latestOut, out)
		}
		if !fitShelves(m, slots) {
			return plan, false
		}
		for _, s := range slots {
			if s.Out < m.serveAt-m.Dishes[s.Dish].RestMax-1e-9 {
				return plan, false
			}
		}
		start := math.Inf(1)
		for _, s := range slots {
			start = math.Min(start, s.In)
		}
		plan.Phases = append([]Phase{{Temp: T, Start: start, End: latestOut}}, plan.Phases...)
		plan.Slots = append(plan.Slots, slots...)
		if p > 0 {
			end = start - transition(temps[p-1], T)
		}
	}
	// Phases can't overlap (a later phase's start must follow an earlier phase's end plus the change).
	for p := 1; p < len(plan.Phases); p++ {
		if plan.Phases[p].Start < plan.Phases[p-1].End+transition(plan.Phases[p-1].Temp, plan.Phases[p].Temp)-1e-9 {
			return plan, false
		}
	}
	first := plan.Phases[0]
	plan.On = plan.Phases[len(plan.Phases)-1].End - first.Start + transition(Room, first.Temp)
	for _, s := range plan.Slots {
		plan.Wait += (m.serveAt - s.Out) - m.Dishes[s.Dish].RestMin
	}
	return plan, true
}

// fitShelves places the dishes of one phase so the shelves never hold more than they can. The
// dishes that can wait least go in first, as late as they're allowed; each later one comes out at the
// latest time it fits: its own latest time, or the moment a dish already placed goes in.
func fitShelves(m *Meal, slots []Slot) bool {
	sort.SliceStable(slots, func(a, b int) bool {
		ra, rb := m.Dishes[slots[a].Dish].RestMax, m.Dishes[slots[b].Dish].RestMax
		if ra != rb {
			return ra < rb
		}
		return slots[a].Out > slots[b].Out
	})
	for k := range slots {
		dur := slots[k].Out - slots[k].In
		candidates := []float64{slots[k].Out}
		for j := 0; j < k; j++ {
			if slots[j].In < slots[k].Out {
				candidates = append(candidates, slots[j].In)
			}
		}
		sort.Sort(sort.Reverse(sort.Float64Slice(candidates)))
		placed := false
		for _, out := range candidates {
			if fits(m, slots[:k], m.Dishes[slots[k].Dish].Space, out-dur, out) {
				slots[k].In, slots[k].Out = out-dur, out
				placed = true
				break
			}
		}
		if !placed {
			return false
		}
	}
	return true
}

// fits reports whether a dish taking `space` can be in from `in` to `out` alongside the others.
func fits(m *Meal, others []Slot, space, in, out float64) bool {
	points := []float64{in}
	for _, o := range others {
		if o.In > in && o.In < out {
			points = append(points, o.In)
		}
	}
	for _, t := range points {
		used := space
		for _, o := range others {
			if o.In <= t+1e-9 && t < o.Out-1e-9 {
				used += m.Dishes[o.Dish].Space
			}
		}
		if used > m.Shelves+1e-9 {
			return false
		}
	}
	return true
}

func better(a, b Plan) bool {
	if len(a.Phases) != len(b.Phases) {
		return len(a.Phases) < len(b.Phases)
	}
	if math.Abs(a.On-b.On) > 1e-6 {
		return a.On < b.On
	}
	return a.Wait < b.Wait
}

// Budget caps how many schedules Best will try, so the largest meal can't hang it.
const Budget = 4_000_000

// Best tries every way of grouping the dishes into one, then two, then up to four temperature
// phases, every order of the groups and the temperatures each group could share (the coolest, the
// hottest, and the one nearest their recipes), and keeps the plan with the fewest phases, then the
// least oven time, then the freshest food. Complete reports whether the search finished in budget.
func Best(m *Meal) (plan Plan, found, complete bool) {
	n := len(m.Dishes)
	tries := 0
	for k := 1; k <= MaxPhases && k <= n && !found; k++ {
		assign := make([]int, n)
		var walk func(i, used int)
		walk = func(i, used int) {
			if tries > Budget {
				return
			}
			if n-i < k-used { // not enough dishes left to fill the remaining groups
				return
			}
			if i == n {
				g := make([][]int, k)
				for d, p := range assign {
					g[p] = append(g[p], d)
				}
				tryGroups(m, g, &plan, &found, &tries)
				return
			}
			for p := 0; p <= used && p < k; p++ {
				assign[i] = p
				if p == used {
					walk(i+1, used+1)
				} else {
					walk(i+1, used)
				}
			}
		}
		walk(0, 0)
	}
	return plan, found, tries <= Budget
}

// shared lists the temperatures a group of dishes can all cook at, keeping the coolest, the hottest
// and the one nearest the average of their recipes.
func shared(m *Meal, members []int) []float64 {
	var all []float64
	for _, t := range candidates(m.Dishes[members[0]]) {
		ok := true
		for _, i := range members[1:] {
			if t < m.Dishes[i].Low || t > m.Dishes[i].High {
				ok = false
				break
			}
		}
		if ok {
			all = append(all, t)
		}
	}
	if len(all) <= 3 {
		return all
	}
	mean := 0.0
	for _, i := range members {
		mean += m.Dishes[i].Temp
	}
	mean /= float64(len(members))
	near := all[0]
	for _, t := range all {
		if math.Abs(t-mean) < math.Abs(near-mean) {
			near = t
		}
	}
	out := []float64{all[0], all[len(all)-1]}
	if !contains(out, near) {
		out = append(out, near)
	}
	return out
}

func tryGroups(m *Meal, g [][]int, best *Plan, found *bool, tries *int) {
	temps := make([][]float64, len(g))
	for p, members := range g {
		if temps[p] = shared(m, members); len(temps[p]) == 0 {
			return
		}
	}
	order := make([]int, len(g))
	for i := range order {
		order[i] = i
	}
	permute(order, 0, func(o []int) {
		og := make([][]int, len(o))
		for i, p := range o {
			og[i] = g[p]
		}
		chosen := make([]float64, len(o))
		var pick func(i int)
		pick = func(i int) {
			if i == len(o) {
				*tries++
				if plan, ok := schedulePhases(m, og, chosen); ok && (!*found || better(plan, *best)) {
					*best, *found = plan, true
				}
				return
			}
			for _, t := range temps[o[i]] {
				chosen[i] = t
				pick(i + 1)
			}
		}
		pick(0)
	})
}

func permute(a []int, k int, f func([]int)) {
	if k == len(a) {
		f(a)
		return
	}
	for i := k; i < len(a); i++ {
		a[k], a[i] = a[i], a[k]
		permute(a, k+1, f)
		a[k], a[i] = a[i], a[k]
	}
}

// Clock formats minutes after midnight (wrapping to the previous day if needed).
func Clock(t float64) string {
	m := int(math.Round(t))
	m = ((m % 1440) + 1440) % 1440
	return fmt.Sprintf("%02d:%02d", m/60, m%60)
}

// ServeAt is serving time in minutes after midnight.
func (m *Meal) ServeAt() float64 { return m.serveAt }
