package hellbox

import (
	"math/rand"
	"strings"
	"testing"
)

func mustCase(t *testing.T, s string) *Case {
	t.Helper()
	c, err := ParseCase("case", s)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func mustJob(t *testing.T, s string) []Page {
	t.Helper()
	p, err := ParseJob("job", s)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestCountsLettersAndLigatures(t *testing.T) {
	p := mustJob(t, "office  fluffy\n")[0]
	if p.Need["f"] != 5 || p.Need["o"] != 1 || p.Need["y"] != 1 || p.Need[" "] != 0 {
		t.Fatalf("need %v", p.Need)
	}
	// "ffi" in office, "ffl"? no: "fluffy" has "fl" then "ff".
	if p.Ligs["ffi"] != 1 || p.Ligs["fl"] != 1 || p.Ligs["ff"] != 1 {
		t.Fatalf("ligatures %v", p.Ligs)
	}
}

func TestSubstitutionsAndLigatures(t *testing.T) {
	c := mustCase(t, "W 1\nV 4\ni 1\nn 4\nu 0\nfi 1\nf 0\n")
	pages := mustJob(t, "WWW finn un\n")
	s := Solve(c, DefaultSubs(), pages, []int{0}, false)
	if !s.OK {
		t.Fatal("should be settable: one W, two Ws from VVVV, the fi ligature, a turned n for u")
	}
	got := map[Glyph]int{}
	for _, u := range s.Subs {
		got[u.For] += u.Count
	}
	if got["W"] != 2 || got["u"] != 1 || s.Ligatures["fi"] != 1 {
		t.Fatalf("subs %+v ligatures %v", s.Subs, s.Ligatures)
	}
	if s.Spare["V"] != 0 || s.Spare["n"] != 0 {
		t.Fatalf("spare %v", s.Spare)
	}
	// Without substitutions it can't be done.
	if Solve(c, nil, pages, []int{0}, false).OK {
		t.Fatal("should need substitutions")
	}
}

func TestPrefersTheRealLetter(t *testing.T) {
	c := mustCase(t, "u 2\nn 5\n")
	s := Solve(c, DefaultSubs(), mustJob(t, "uun"), []int{0}, false)
	if !s.OK || len(s.Subs) != 0 || s.Looks != 0 {
		t.Fatalf("%+v", s)
	}
}

func TestBuysTheFewestSorts(t *testing.T) {
	c := mustCase(t, "a 1\nb 0\nW 0\nV 2\n")
	s := Solve(c, DefaultSubs(), mustJob(t, "aaa bb W"), []int{0}, true)
	if !s.OK {
		t.Fatal("buying always works")
	}
	if s.Buy["a"] != 2 || s.Buy["b"] != 0 && s.Buy["q"] != 0 {
		t.Fatalf("buy %v", s.Buy)
	}
	// b can't come from a turned q (there are none), so two bs are bought; W comes from VV.
	total := 0
	for _, k := range s.Buy {
		total += k
	}
	if total != 4 || s.Buy["W"] != 0 {
		t.Fatalf("buy %v", s.Buy)
	}
}

// Brute force: try every way of meeting each glyph's need from its own sort or a one-sort
// substitute, and keep the cheapest that fits.
func bruteCost(c *Case, subs []Sub, need map[Glyph]int) (int, bool) {
	type opt struct {
		g    Glyph
		sort Glyph
		cost int
	}
	var glyphs []Glyph
	for g, k := range need {
		if k > 0 {
			glyphs = append(glyphs, g)
		}
	}
	best, found := 0, false
	used := map[Glyph]int{}
	var rec func(i int, cost int)
	rec = func(i int, cost int) {
		if i == len(glyphs) {
			if !found || cost < best {
				best, found = cost, true
			}
			return
		}
		g := glyphs[i]
		opts := []opt{{g, g, 0}}
		for _, s := range subs {
			if s.For == g && len(s.Use) == 1 {
				opts = append(opts, opt{g, s.Use[0], s.Cost})
			}
		}
		// Split need[g] among the options in every way.
		var split func(j, left, cost int)
		split = func(j, left, cost int) {
			if j == len(opts)-1 {
				o := opts[j]
				if used[o.sort]+left <= c.Count[o.sort] {
					used[o.sort] += left
					rec(i+1, cost+left*o.cost)
					used[o.sort] -= left
				}
				return
			}
			for k := 0; k <= left; k++ {
				o := opts[j]
				if used[o.sort]+k > c.Count[o.sort] {
					break
				}
				used[o.sort] += k
				split(j+1, left-k, cost+k*o.cost)
				used[o.sort] -= k
			}
		}
		split(0, need[g], cost)
	}
	rec(0, 0)
	return best, found
}

func TestFlowMatchesBruteForce(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	letters := []Glyph{"a", "b", "c", "d"}
	for trial := 0; trial < 300; trial++ {
		c := &Case{Count: map[Glyph]int{}}
		need := map[Glyph]int{}
		for _, g := range letters {
			c.Count[g] = rng.Intn(4)
			need[g] = rng.Intn(4)
		}
		var subs []Sub
		for i := 0; i < 4; i++ {
			a, b := letters[rng.Intn(4)], letters[rng.Intn(4)]
			if a != b {
				subs = append(subs, Sub{a, []Glyph{b}, 1 + rng.Intn(4), ""})
			}
		}
		var text strings.Builder
		for _, g := range letters {
			text.WriteString(strings.Repeat(string(g), need[g]))
		}
		if text.Len() == 0 {
			continue
		}
		pages := []Page{pageOf("p", text.String())}
		got := Solve(c, subs, pages, []int{0}, false)
		want, ok := bruteCost(c, subs, need)
		if got.OK != ok || (ok && got.Looks != want) {
			t.Fatalf("trial %d: case %v need %v subs %v: got ok=%v looks=%d, want ok=%v looks=%d", trial, c.Count, need, subs, got.OK, got.Looks, ok, want)
		}
		if ok {
			total, left := 0, 0
			for _, k := range c.Count {
				total += k
			}
			for _, k := range got.Spare {
				left += k
			}
			if total-left != got.Letters {
				t.Fatalf("trial %d: %d sorts used for %d letters", trial, total-left, got.Letters)
			}
		}
	}
}

// Every partition of a small job into formes, to check the planner finds the fewest.
func fewestByBrute(c *Case, subs []Sub, pages []Page, per int) int {
	n := len(pages)
	best := n + 1
	assign := make([]int, n)
	var rec func(i, groups int)
	rec = func(i, groups int) {
		if groups >= best {
			return
		}
		if i == n {
			for g := 0; g < groups; g++ {
				var list []int
				for j, a := range assign {
					if a == g {
						list = append(list, j)
					}
				}
				if len(list) > per || !Solve(c, subs, pages, list, false).OK {
					return
				}
			}
			best = groups
			return
		}
		for g := 0; g <= groups; g++ {
			assign[i] = g
			next := groups
			if g == groups {
				next++
			}
			rec(i+1, next)
		}
	}
	rec(0, 0)
	return best
}

func TestPlannerFindsTheFewestFormes(t *testing.T) {
	rng := rand.New(rand.NewSource(11))
	words := []string{"ant", "bee", "cat", "dot", "eel", "fan", "gnu", "hen", "inn", "jot", "tea", "net"}
	for trial := 0; trial < 40; trial++ {
		c := &Case{Name: "t", Count: map[Glyph]int{}}
		for _, r := range "abcdefghijnotu" {
			c.Count[Glyph(r)] = 2 + rng.Intn(4)
		}
		n := 3 + rng.Intn(4)
		var pages []Page
		for i := 0; i < n; i++ {
			pages = append(pages, pageOf("p", words[rng.Intn(len(words))]+" "+words[rng.Intn(len(words))]))
		}
		per := 1 + rng.Intn(4)
		plan := PlanJob(c, DefaultSubs(), pages, per)
		if len(plan.Alone) > 0 {
			continue
		}
		want := fewestByBrute(c, DefaultSubs(), pages, per)
		if len(plan.Formes) != want || !plan.Exact {
			t.Fatalf("trial %d: %d formes, fewest is %d", trial, len(plan.Formes), want)
		}
		if plan.LowerBound > want {
			t.Fatalf("trial %d: lower bound %d above the answer %d", trial, plan.LowerBound, want)
		}
		seen := map[int]bool{}
		for _, f := range plan.Formes {
			if len(f.Pages) > per || !f.OK {
				t.Fatalf("trial %d: bad forme %+v", trial, f)
			}
			for _, p := range f.Pages {
				seen[p] = true
			}
		}
		if len(seen) != n {
			t.Fatalf("trial %d: pages lost", trial)
		}
	}
}

func TestShoppingMakesItFit(t *testing.T) {
	c := mustCase(t, "a 2\nb 1\n")
	pages := mustJob(t, "aaa\n---\nab\n---\nbbb\n")
	buy := Shopping(c, nil, pages, 3, 1)
	more := &Case{Count: map[Glyph]int{"a": 2 + buy["a"], "b": 1 + buy["b"]}}
	if !Solve(more, nil, pages, []int{0, 1, 2}, false).OK {
		t.Fatalf("after buying %v it still doesn't fit", buy)
	}
	if buy["a"] != 2 || buy["b"] != 3 {
		t.Fatalf("buy %v", buy)
	}
}

func TestHostileInput(t *testing.T) {
	cases := []struct {
		text, want string
	}{
		{"a 5\na 3\n", "listed twice"},
		{"a -1\n", "whole number"},
		{"a 99999999999999999999\n", "whole number"},
		{"a five\n", "whole number"},
		{"abcd 1\n", "1 to 3 printable"},
		{"\x01 1\n", "1 to 3 printable"},
		{"‮ 1\n", "1 to 3 printable"},
		{"a 1 2\n", "<glyph> <count>"},
		{"\xff\xfe 1\n", "UTF-8"},
		{"a 1\x00\n", "not a text file"},
		{strings.Repeat("x", MaxFileBytes+1), "256 KB"},
		{"// only a comment\n", "no sorts"},
		{"a 1\n" + strings.Repeat("b", 5000) + " 1\n", "too long"},
	}
	for _, tc := range cases {
		_, err := ParseCase("case", tc.text)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%q: got %v, want %q", tc.text[:min(len(tc.text), 20)], err, tc.want)
			continue
		}
		if strings.Contains(err.Error(), "five") || strings.ContainsAny(err.Error(), "\x01‮\x00") {
			t.Errorf("error repeats the input: %v", err)
		}
	}
	jobs := []struct{ text, want string }{
		{"", "nothing to set"},
		{"---\n---\n", "nothing to set"},
		{"hello‮world", "control characters"},
		{"bell\a", "control characters"},
		{strings.Repeat("a\n---\n", MaxPages+1), "at most 200 pages"},
	}
	for _, tc := range jobs {
		_, err := ParseJob("job", tc.text)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("job %q: got %v, want %q", tc.text[:min(len(tc.text), 20)], err, tc.want)
		}
	}
	subs := []struct{ text, want string }{
		{"W = V V\n", "0 to 100"},
		{"W = V V 1000\n", "0 to 100"},
		{"W = A B C D 1\n", "at most 3"},
		{"W VV 1\n", "<cost>"},
	}
	for _, tc := range subs {
		_, err := ParseSubs("subs", tc.text)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("subs %q: got %v, want %q", tc.text, err, tc.want)
		}
	}
	if got := Show("‮"); got != "U+202E" {
		t.Errorf("Show: %q", got)
	}
}

func TestBiggestJobStaysBounded(t *testing.T) {
	var sb strings.Builder
	for i := 0; i < 40; i++ {
		sb.WriteString(strings.Repeat("WW wwuu \"0 1 ", 20))
		sb.WriteString("\n---\n")
	}
	c := mustCase(t, "W 3\nV 9\nw 2\nv 9\nu 4\nn 9\n\" 1\n' 9\n0 1\nO 9\n1 1\nl 9\nI 9\n")
	pages := mustJob(t, sb.String())
	plan := PlanJob(c, DefaultSubs(), pages, 4)
	if len(plan.Formes)+len(plan.Alone) == 0 {
		t.Fatal("no plan")
	}
	if plan.Exact && len(plan.Formes) < plan.LowerBound {
		t.Fatal("beat the lower bound")
	}
}

func FuzzParse(f *testing.F) {
	f.Add("a 3\nW 1\n", "WaW\n---\naa")
	f.Fuzz(func(t *testing.T, cs, js string) {
		c, err1 := ParseCase("case", cs)
		p, err2 := ParseJob("job", js)
		if err1 != nil || err2 != nil || len(p) > 4 {
			return
		}
		PlanJob(c, DefaultSubs(), p, 2)
	})
}
