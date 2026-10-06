package planner

import (
	"math/rand"
	"os"
	"strings"
	"testing"
	"time"
)

const plenty = 5_000_000

func mustParse(t *testing.T, text string) *Problem {
	t.Helper()
	p, err := Parse(text)
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	return p
}

func example(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile("../../examples/" + name)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestSolverAgreesWithBruteForce(t *testing.T) {
	r := rand.New(rand.NewSource(2026))
	feasible, impossible := 0, 0
	for trial := 0; trial < 3000; trial++ {
		p := randomProblem(r)
		selection := Everything(p)
		wantFound, wantDays, wantIdle := bruteForce(p, selection)
		got := Solve(p, selection, true, plenty)
		if got.LimitHit {
			t.Fatalf("trial %d: limit hit on a tiny problem", trial)
		}
		if got.Found != wantFound {
			t.Fatalf("trial %d: solver found=%v, brute force found=%v", trial, got.Found, wantFound)
		}
		if !got.Found {
			impossible++
			continue
		}
		feasible++
		if !valid(p, selection, got.Picks) {
			t.Fatalf("trial %d: solver returned a timetable that breaks a rule", trial)
		}
		if got.Days != wantDays || got.IdleMinutes != wantIdle {
			t.Fatalf("trial %d: solver (%d days, %d idle) is not the optimum (%d days, %d idle)",
				trial, got.Days, got.IdleMinutes, wantDays, wantIdle)
		}
		if quick := Solve(p, selection, false, plenty); !quick.Found || !valid(p, selection, quick.Picks) {
			t.Fatalf("trial %d: first-solution mode failed", trial)
		}
	}
	if feasible < 500 || impossible < 500 {
		t.Fatalf("test data is lopsided: %d feasible, %d impossible", feasible, impossible)
	}
}

func TestEveryComponentGetsExactlyOnePick(t *testing.T) {
	p := mustParse(t, example(t, "first-year.txt"))
	solution := Solve(p, Everything(p), true, plenty)
	if !solution.Found {
		t.Fatal("expected a timetable")
	}
	seen := map[[2]int]int{}
	for _, pick := range solution.Picks {
		seen[[2]int{pick.Course, pick.Component}]++
	}
	total := 0
	for ci, course := range p.Courses {
		for ki := range course.Components {
			total++
			if seen[[2]int{ci, ki}] != 1 {
				t.Fatalf("%s %s picked %d times", course.Code, course.Components[ki].Name, seen[[2]int{ci, ki}])
			}
		}
	}
	if len(solution.Picks) != total {
		t.Fatalf("picks = %d, components = %d", len(solution.Picks), total)
	}
}

func TestEachWishKindIsEnforced(t *testing.T) {
	base := "AAA\n Lecture: Mon 09:00-11:00 | Fri 16:00-18:00\nBBB\n Lecture: Mon 11:00-12:00 | Tue 12:00-14:00\n"
	cases := []struct {
		wish     string
		wantDays int
		possible bool
	}{
		{"", 1, true},
		{"wish: no classes on Mon", 2, true},
		{"wish: nothing before 10:00", 2, true},
		{"wish: nothing after 12:00", 1, true},
		{"wish: at least 10 min between classes", 2, true},
		{"wish: at most 2 hours per day", 2, true},
		{"wish: at most 1 days", 1, true},
		{"wish: busy Mon 08:00-12:00 gym", 2, true},
		{"wish: lunch 12:00-14:00 for 60 min\nwish: no Mon", 2, false}, // BBB Tue fills 12-14, AAA Fri fine, but BBB has no lunch
		{"wish: no Mon\nwish: no Fri", 0, false},
		{"wish: nothing before 12:00\nwish: nothing after 13:00", 0, false},
	}
	for _, c := range cases {
		p := mustParse(t, base+c.wish)
		got := Solve(p, Everything(p), true, plenty)
		if got.Found != c.possible {
			t.Errorf("%q: found=%v, want %v", c.wish, got.Found, c.possible)
			continue
		}
		if got.Found && got.Days != c.wantDays {
			t.Errorf("%q: days=%d, want %d", c.wish, got.Days, c.wantDays)
		}
	}
}

func TestLunchBreakDetails(t *testing.T) {
	m := func(start, end int) Meeting { return Meeting{Start: start * 60, End: end * 60} }
	cases := []struct {
		meetings []Meeting
		needed   int
		want     bool
	}{
		{nil, 60, true},
		{[]Meeting{m(12, 14)}, 1, false},
		{[]Meeting{m(12, 13)}, 60, true},
		{[]Meeting{m(12, 13)}, 61, false},
		{[]Meeting{m(11, 13), {Start: 13*60 + 30, End: 15 * 60}}, 30, true},
		{[]Meeting{m(11, 13), {Start: 13*60 + 30, End: 15 * 60}}, 31, false},
		{[]Meeting{m(14, 16), m(9, 12)}, 120, true}, // unsorted input
		{[]Meeting{m(8, 18)}, 5, false},
	}
	for i, c := range cases {
		if got := hasFreeStretch(c.meetings, 12*60, 14*60, c.needed); got != c.want {
			t.Errorf("case %d: got %v, want %v", i, got, c.want)
		}
	}
}

func TestNodeLimitIsRespected(t *testing.T) {
	p := mustParse(t, example(t, "first-year.txt"))
	solution := Solve(p, Everything(p), true, 10)
	if solution.Nodes > 11 || !solution.LimitHit {
		t.Fatalf("nodes=%d limitHit=%v", solution.Nodes, solution.LimitHit)
	}
	if solution.Found || solution.Definite() {
		t.Fatal("an unfinished search must not claim a definite answer")
	}
}

// The largest input the parser accepts, built to be as hard as possible:
// every option clashes only late in the search.
func worstCase() string {
	var b strings.Builder
	days := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	for c := 0; c < MaxCourses; c++ {
		b.WriteString("C" + string(rune('A'+c)) + "\n")
		for k := 0; k < MaxComponents; k++ {
			b.WriteString(" Part:")
			for o := 0; o < MaxOptions; o++ {
				if o > 0 {
					b.WriteString(" |")
				}
				hour := 6 + (o+c+k)%16
				b.WriteString(" " + days[(o+c*k)%7] + " " + Clock(hour*60) + "-" + Clock(hour*60+60))
			}
			b.WriteString("\n")
		}
	}
	b.WriteString("wish: at most 2 days\nwish: lunch 11:00-15:00 for 200 min\nwish: at least 30 min between classes\n")
	return b.String()
}

func TestWorstCaseInputFinishesInBoundedTime(t *testing.T) {
	started := time.Now()
	response := Run(worstCase())
	elapsed := time.Since(started)
	if response.Nodes > MainSolveNodes+ExplainNodes+ExplainPerSolve {
		t.Fatalf("did %d search steps, more than the budget", response.Nodes)
	}
	if elapsed > 30*time.Second {
		t.Fatalf("took %v", elapsed)
	}
	t.Logf("worst case: status=%s nodes=%d in %v", response.Status, response.Nodes, elapsed)
}
