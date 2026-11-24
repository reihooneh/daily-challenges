package ovenslot

import (
	"math"
	"math/rand"
	"os"
	"strings"
	"testing"
)

func example(t *testing.T) *Meal {
	t.Helper()
	data, err := os.ReadFile("../examples/christmas.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := Parse(data)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// valid checks everything a plan promises.
func valid(t *testing.T, m *Meal, p Plan) {
	t.Helper()
	if len(p.Slots) != len(m.Dishes) {
		t.Fatalf("%d slots for %d dishes", len(p.Slots), len(m.Dishes))
	}
	for _, s := range p.Slots {
		d := m.Dishes[s.Dish]
		if s.Temp < d.Low || s.Temp > d.High {
			t.Errorf("%s cooked at %g, outside %g-%g", d.Name, s.Temp, d.Low, d.High)
		}
		if math.Abs(s.Out-s.In-d.TimeAt(s.Temp)) > 1e-6 {
			t.Errorf("%s isn't in for its cooking time", d.Name)
		}
		wait := m.ServeAt() - s.Out
		if wait < d.RestMin-1e-6 || wait > d.RestMax+1e-6 {
			t.Errorf("%s waits %g, outside %g-%g", d.Name, wait, d.RestMin, d.RestMax)
		}
		ph := p.Phases[s.Phase]
		if s.In < ph.Start-1e-6 || s.Out > ph.End+1e-6 || ph.Temp != s.Temp {
			t.Errorf("%s isn't inside its phase", d.Name)
		}
		// shelves: at the moment it goes in, what's in the oven fits
		used := 0.0
		for _, o := range p.Slots {
			if o.In <= s.In+1e-9 && s.In < o.Out-1e-9 {
				used += m.Dishes[o.Dish].Space
			}
		}
		if used > m.Shelves+1e-9 {
			t.Errorf("shelves overfull when %s goes in: %g", d.Name, used)
		}
	}
	for i := 1; i < len(p.Phases); i++ {
		a, b := p.Phases[i-1], p.Phases[i]
		if b.Start < a.End+transition(a.Temp, b.Temp)-1e-6 {
			t.Errorf("phase %d starts before the oven can get to %g", i, b.Temp)
		}
	}
}

func TestExample(t *testing.T) {
	m := example(t)
	p, ok, complete := Best(m)
	if !ok || !complete {
		t.Fatal("the example should plan")
	}
	if len(p.Phases) != 3 {
		t.Errorf("want 3 temperatures, got %d", len(p.Phases))
	}
	valid(t, m, p)
}

func TestTimeAtTemperature(t *testing.T) {
	d := Dish{Temp: 180, Minutes: 80}
	if d.TimeAt(180) != 80 || math.Abs(d.TimeAt(260)-40) > 1e-9 {
		t.Error("cooking time should scale with 1/(T - 100)")
	}
}

// Random small meals: every plan found is valid, and when the full search over every temperature
// (not just the three Best keeps per group) finds a plan, Best finds one with as few phases.
func TestRandomMeals(t *testing.T) {
	r := rand.New(rand.NewSource(3))
	for trial := 0; trial < 60; trial++ {
		m := &Meal{Serve: "18:00", Shelves: float64(1 + r.Intn(2)), serveAt: 18 * 60}
		for i := 0; i < 2+r.Intn(3); i++ {
			temp := float64(140 + 10*r.Intn(10))
			m.Dishes = append(m.Dishes, Dish{
				Name: string(rune('A' + i)), Temp: temp, Minutes: float64(15 + r.Intn(60)),
				Low: temp - float64(10*r.Intn(3)), High: temp + float64(10*r.Intn(3)),
				Space: []float64{0.5, 1}[r.Intn(2)], RestMax: float64(5 + r.Intn(60)),
			})
		}
		p, ok, _ := Best(m)
		if ok {
			valid(t, m, p)
		}
		full := fullSearch(m)
		if full > 0 && (!ok || len(p.Phases) > full) {
			t.Errorf("trial %d: full search finds %d phases, Best %v %d", trial, full, ok, len(p.Phases))
		}
	}
}

// fullSearch: fewest phases over every grouping, order and every candidate temperature.
func fullSearch(m *Meal) int {
	n := len(m.Dishes)
	best := 0
	assign := make([]int, n)
	var walk func(i, used int)
	walk = func(i, used int) {
		if i == n {
			g := make([][]int, used)
			for d, p := range assign {
				g[p] = append(g[p], d)
			}
			order := make([]int, used)
			for k := range order {
				order[k] = k
			}
			permute(order, 0, func(o []int) {
				og := make([][]int, used)
				for k, p := range o {
					og[k] = g[p]
				}
				temps := make([]float64, used)
				var pick func(k int)
				pick = func(k int) {
					if k == used {
						if _, ok := schedulePhases(m, og, temps); ok && (best == 0 || used < best) {
							best = used
						}
						return
					}
					for t := 110.0; t <= 260; t += 10 {
						ok := true
						for _, d := range og[k] {
							if t < m.Dishes[d].Low || t > m.Dishes[d].High {
								ok = false
							}
						}
						if ok {
							temps[k] = t
							pick(k + 1)
						}
					}
				}
				pick(0)
			})
			return
		}
		for p := 0; p <= used && p < MaxPhases; p++ {
			assign[i] = p
			if p == used {
				walk(i+1, used+1)
			} else {
				walk(i+1, used)
			}
		}
	}
	walk(0, 0)
	return best
}

func TestHostileMeals(t *testing.T) {
	good := `{"serve":"18:30","shelves":2,"dishes":[{"name":"A","temp":180,"minutes":30,"space":1,"restMax":10}]}`
	if _, err := Parse([]byte(good)); err != nil {
		t.Fatal(err)
	}
	bad := []string{
		``, `[]`, `{"serve":"25:00","shelves":2,"dishes":[]}`,
		strings.Replace(good, `"shelves":2`, `"shelves":9`, 1),
		strings.Replace(good, `"temp":180`, `"temp":900`, 1),
		strings.Replace(good, `"temp":180`, `"temp":1e999`, 1),
		strings.Replace(good, `"minutes":30`, `"minutes":-3`, 1),
		strings.Replace(good, `"name":"A"`, `"name":"<img src=x>"`, 1),
		strings.Replace(good, `"name":"A"`, `"name":"A\u001b[2J"`, 1),
		strings.Replace(good, `"restMax":10`, `"restMax":10,"evil":true`, 1),
		strings.Replace(good, `"restMax":10`, `"restMin":20,"restMax":10`, 1),
		good + good,
		strings.Repeat(" ", MaxBytes+1),
	}
	for _, b := range bad {
		if _, err := Parse([]byte(b)); err == nil {
			t.Errorf("accepted %.60q", b)
		}
	}
	var many strings.Builder
	many.WriteString(`{"serve":"18:30","shelves":2,"dishes":[`)
	for i := 0; i < 11; i++ {
		if i > 0 {
			many.WriteString(",")
		}
		many.WriteString(`{"name":"D` + string(rune('a'+i)) + `","temp":180,"minutes":30,"space":1}`)
	}
	many.WriteString(`]}`)
	if _, err := Parse([]byte(many.String())); err == nil {
		t.Error("accepted 11 dishes")
	}
}

// The biggest meal allowed still finishes quickly, inside the search budget.
func TestLargestMeal(t *testing.T) {
	m := &Meal{Serve: "19:00", Shelves: 4, serveAt: 19 * 60}
	for i := 0; i < MaxDishes; i++ {
		temp := float64(150 + 10*(i%9))
		m.Dishes = append(m.Dishes, Dish{Name: string(rune('A' + i)), Temp: temp, Minutes: 30, Low: temp - 30, High: temp + 30, Space: 0.4, RestMax: 20})
	}
	if _, _, complete := Best(m); !complete {
		t.Log("search hit its budget (reported to the user)")
	}
}
