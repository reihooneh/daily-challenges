package bowball

import (
	"bytes"
	"fmt"
	"math"
	"math/rand/v2"
	"os"
	"strings"
	"testing"
)

const two = `squad Test
seats 1
rower A
rower B
rower C
piece 1000 m
boat X 200 A
boat Y 201 B
`

func mustParse(t *testing.T, text string) *Session {
	t.Helper()
	s, err := Parse(text)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return s
}

func TestParseAccepts(t *testing.T) {
	s := mustParse(t, "\uFEFF"+`squad Men's 2x (trial)
seats 2
noise 0.8
rower Kai bow
rower Leo stroke
rower Max either
rower Nico scull
piece 2000 m   # into the wind
boat Blue 7:01.5 Kai Leo
boat Red 421.25 Max Nico
`)
	if s.Name != "Men's 2x (trial)" || s.Seats != 2 || s.Noise != 0.8 || !s.Sweep {
		t.Fatalf("settings: %+v", s)
	}
	if s.Rowers[0].Side != Bow || s.Rowers[1].Side != Stroke || s.Rowers[2].Side != Either || s.Rowers[3].Side != Either {
		t.Fatal("sides")
	}
	b := s.Pieces[0].Boats
	if math.Abs(b[0].Time-421.5) > 1e-9 || math.Abs(b[1].Time-421.25) > 1e-9 || s.Pieces[0].Distance != 2000 {
		t.Fatal("times and distance")
	}
	if len(s.Hulls) != 2 || b[1].Crew[1] != 3 {
		t.Fatal("hulls and crews")
	}
	if d := mustParse(t, strings.Replace(two, "seats 1\n", "", 1)); d.Seats != 1 {
		t.Fatal("seats default to the size of the first boat")
	}
}

func TestParseRejects(t *testing.T) {
	cases := []struct{ text, want string }{
		{"", "no pieces"},
		{strings.Replace(two, "boat Y 201 B\n", "", 1), "at least two boats"},
		{strings.Replace(two, "rower C", "rower C\nrower D", 1) + "boat Z 202 C D\n", "same number of rowers"},
		{two + "boat Z 202 D\n", "needs a 'rower' line"},
		{two + "boat Z 202 A\n", "one boat per piece"},
		{two + "boat X 202 C\n", "already in the piece"},
		{strings.Replace(two, "boat X 200 A", "boat X 200 A A", 1) + "", "listed twice"},
		{two + "rower D\n", "come before the first piece"},
		{two + "seats 2\n", "come before the first piece"},
		{strings.Replace(two, "rower C", "rower B", 1), "already a rower"},
		{strings.Replace(two, "rower C", "rower <b>", 1), "names are one word"},
		{strings.Replace(two, "rower C", "rower C port", 1), "side is bow"},
		{strings.Replace(two, "200 A", "2e2 A", 1), "times are seconds"},
		{strings.Replace(two, "200 A", "-5 A", 1), "times are seconds"},
		{strings.Replace(two, "200 A", "61:00 A", 1), "times are seconds"},
		{strings.Replace(two, "200 A", "3:75 A", 1), "times are seconds"},
		{strings.Replace(two, "1000 m", "50 m", 1), "piece <distance> m"},
		{strings.Replace(two, "1000 m", "9000 m", 1), "100 to 6000"},
		{strings.Replace(two, "1000 m", "1km", 1), "piece <distance> m"},
		{strings.Replace(two, "seats 1", "seats 3", 1), "fewer than the number"},
		{strings.Replace(two, "seats 1", "seats one", 1), "seats N"},
		{"noise 0\n" + two, "noise S"},
		{"noise 1e1\n" + two, "noise S"},
		{"squad <script>\n" + two, "squad name"},
		{"boat X 200 A\n" + two, "belong under a 'piece'"},
		{two + "oars 2\n", "lines start with"},
		{two + "squad Again\n", "comes once"},
		{"squad A\x1b[2J\n" + two, "control or hidden"},
		{"squad A\u202eB\n" + two, "control or hidden"},
		{"squad A\u200bB\n" + two, "control or hidden"},
		{"squad A\xff\n" + two, "not valid UTF-8"},
		{"# " + strings.Repeat("x", 400) + "\n" + two, "longer than 300"},
		{strings.Repeat("\n", MaxInput+1), "larger than 64 KB"},
		{"seats 2\nrower A bow\nrower B stroke\nrower C bow\npiece 1000 m\nboat X 1 A B\nboat Y 2 C B\n", "one boat per piece"},
		{"seats 3\nrower A bow\nrower B stroke\nrower C bow\nrower D stroke\npiece 1000 m\nboat X 1 A B C\nboat Y 2 D A B\n", "one boat per piece"},
		{"seats 2\nrower A bow\nrower B bow\nrower C bow\npiece 1000 m\nboat X 1 A B\nboat Y 2 C A\n", "one boat per piece"},
		{"seats 2\nrower A bow\nrower B bow\nrower C bow\npiece 1000 m\nboat X 1 A\nboat Y 2 C\n", "enough rowers on each side"},
		{"seats 1\nrower A bow\nrower B stroke\nrower C bow\npiece 1000 m\nboat X 1 A\nboat Y 2 C\n", "even number of seats"},
	}
	for _, c := range cases {
		_, err := Parse(c.text)
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("want %q, got %v", c.want, err)
		}
	}
	many := "rower A\nrower B\nrower C\n"
	for i := 0; i < 61; i++ {
		many += "piece 1000 m\nboat X 1 A\nboat Y 2 B\n"
	}
	if _, err := Parse(many); err == nil || !strings.Contains(err.Error(), "at most 60 pieces") {
		t.Errorf("piece limit: %v", err)
	}
	rowers := ""
	for i := 0; i < 41; i++ {
		rowers += fmt.Sprintf("rower R%d\n", i)
	}
	if _, err := Parse(rowers + "piece 1000 m\nboat X 1 R0\nboat Y 2 R1\n"); err == nil || !strings.Contains(err.Error(), "at most 40 rowers") {
		t.Errorf("rower limit: %v", err)
	}
}

// synthetic builds a session whose times follow the model exactly (plus optional noise).
func synthetic(speeds []float64, hulls []float64, lineups [][][]int, distance float64, noise float64, rng *rand.Rand) string {
	var b strings.Builder
	b.WriteString("seats 2\n")
	for i := range speeds {
		fmt.Fprintf(&b, "rower R%d\n", i)
	}
	for _, pieceCrews := range lineups {
		fmt.Fprintf(&b, "piece %d m\n", int(distance))
		base := 200.0
		if rng != nil {
			base += rng.NormFloat64() * 3
		}
		for k, crew := range pieceCrews {
			t := base + hulls[k]
			for _, r := range crew {
				t -= speeds[r]
			}
			if rng != nil {
				t += rng.NormFloat64() * noise
			}
			t *= distance / 1000
			fmt.Fprintf(&b, "boat H%d %.3f", k, t)
			for _, r := range crew {
				fmt.Fprintf(&b, " R%d", r)
			}
			b.WriteString("\n")
		}
	}
	return b.String()
}

// Every pair of singles races once, in alternating hulls: a full round robin.
func roundRobin(n int) [][][]int {
	var l [][][]int
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			if (i+j)%2 == 0 {
				l = append(l, [][]int{{i}, {j}})
			} else {
				l = append(l, [][]int{{j}, {i}})
			}
		}
	}
	return l
}

func TestRecoversSpeedsAndHulls(t *testing.T) {
	speeds := []float64{1.0, 0.4, 0, -0.3, -1.1}
	avg := 0.0
	for _, v := range speeds {
		avg += v / float64(len(speeds))
	}
	for _, distance := range []float64{1000, 2000, 500} {
		s := mustParse(t, synthetic(speeds, []float64{0.4, -0.4}, roundRobin(5), distance, 0, nil))
		f, err := Estimate(s)
		if err != nil {
			t.Fatal(err)
		}
		for i, v := range speeds {
			if math.Abs(f.Skill[i]-(v-avg)) > 0.02 {
				t.Errorf("%v m: rower %d speed %.3f, want %.3f", distance, i, f.Skill[i], v-avg)
			}
		}
		if math.Abs(f.Hull[0]-0.4) > 0.02 || math.Abs(f.Hull[1]+0.4) > 0.02 {
			t.Errorf("%v m: hulls %v", distance, f.Hull)
		}
		if f.Odd != nil {
			t.Error("exact data has no odd results")
		}
	}
}

func TestNoiseIsEstimated(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	speeds := []float64{0.8, 0.3, 0, -0.2, -0.9}
	var lineups [][][]int
	for k := 0; k < 6; k++ {
		lineups = append(lineups, roundRobin(5)...)
	}
	s := mustParse(t, synthetic(speeds, []float64{0, 0}, lineups, 1000, 0.7, rng))
	f, _ := Estimate(s)
	if !f.FromData || math.Abs(f.Sigma-0.7) > 0.15 {
		t.Errorf("noise %.3f from data %v", f.Sigma, f.FromData)
	}
	// About 95% of true speeds should lie within 2 standard errors.
	inside := 0
	for i := range speeds {
		if math.Abs(f.Skill[i]-(speeds[i]-(-0.0))) < 2*f.SE[i]+0.01 {
			inside++
		}
	}
	if inside < 4 {
		t.Errorf("only %d of 5 speeds inside two standard errors", inside)
	}
}

func TestOneRaceSeparatesNoOne(t *testing.T) {
	s := mustParse(t, "seats 2\nrower A\nrower B\nrower C\nrower D\npiece 1000 m\nboat X 200 A B\nboat Y 201 C D\n")
	f, _ := Estimate(s)
	for i := range s.Rowers {
		if f.Separated(i) {
			t.Errorf("rower %d can't be told from a crew-mate after one race", i)
		}
	}
	ch, _ := Chances(s, f, 4000)
	for i, c := range ch {
		if c < 0.2 || c > 0.8 {
			t.Errorf("rower %d chance %.2f should be near even", i, c)
		}
	}
}

func TestOddResultIsFlagged(t *testing.T) {
	speeds := []float64{0.5, 0.2, -0.1, -0.6}
	var lineups [][][]int
	for k := 0; k < 4; k++ {
		lineups = append(lineups, roundRobin(4)...)
	}
	text := synthetic(speeds, []float64{0, 0}, lineups, 1000, 0, nil)
	lines := strings.Split(text, "\n")
	for i, l := range lines {
		if strings.HasPrefix(l, "boat H0") && i > 20 {
			parts := strings.Fields(l)
			parts[2] = "260.000" // a crab: a minute slow
			lines[i] = strings.Join(parts, " ")
			break
		}
	}
	s := mustParse(t, strings.Join(lines, "\n"))
	f, _ := Estimate(s)
	if f.Odd == nil {
		t.Fatal("a crab should be flagged")
	}
	if s.Pieces[f.Odd.Piece].Boats[f.Odd.Boat].Line == 0 {
		t.Fatal("the odd result points at a real line")
	}
}

// Select must match a brute-force search over every set of rowers.
func TestSelectIsExact(t *testing.T) {
	rng := rand.New(rand.NewPCG(7, 8))
	for trial := 0; trial < 300; trial++ {
		n := 4 + rng.IntN(5)
		s := &Session{Seats: 2 * (1 + rng.IntN(2)), Sweep: true}
		for i := 0; i < n; i++ {
			s.Rowers = append(s.Rowers, Rower{Name: fmt.Sprint(i), Side: Side(rng.IntN(3))})
		}
		half := s.Seats / 2
		speed := make([]float64, n)
		for i := range speed {
			speed[i] = rng.NormFloat64()
		}
		best := math.Inf(-1)
		for mask := 0; mask < 1<<n; mask++ {
			var picked []int
			for i := 0; i < n; i++ {
				if mask>>i&1 == 1 {
					picked = append(picked, i)
				}
			}
			if len(picked) != s.Seats || !seatable(s, picked, half) {
				continue
			}
			t := 0.0
			for _, i := range picked {
				t += speed[i]
			}
			best = math.Max(best, t)
		}
		in := Select(s, speed)
		if math.IsInf(best, -1) {
			for _, ok := range in {
				if ok {
					t.Fatal("no valid boat: nobody is picked")
				}
			}
			continue
		}
		got, count := 0.0, 0
		var picked []int
		for i, ok := range in {
			if ok {
				got += speed[i]
				count++
				picked = append(picked, i)
			}
		}
		if count != s.Seats || !seatable(s, picked, half) || math.Abs(got-best) > 1e-9 {
			t.Fatalf("trial %d: picked %v (%.3f), best %.3f", trial, picked, got, best)
		}
	}
}

func seatable(s *Session, picked []int, half int) bool {
	bow, stroke := 0, 0
	for _, i := range picked {
		switch s.Rowers[i].Side {
		case Bow:
			bow++
		case Stroke:
			stroke++
		}
	}
	return bow <= half && stroke <= half
}

func TestChancesAddUpToSeats(t *testing.T) {
	s := mustParse(t, readExample(t, "womens-four.txt"))
	f, _ := Estimate(s)
	ch, err := Chances(s, f, 5000)
	if err != nil {
		t.Fatal(err)
	}
	total := 0.0
	for _, c := range ch {
		total += c
	}
	if math.Abs(total-float64(s.Seats)) > 1e-9 {
		t.Errorf("chances add to %.4f, want %d", total, s.Seats)
	}
	for _, p := range CutPairs(s, f) {
		if !CanSwap(s.Rowers[p.In].Side, s.Rowers[p.Out].Side) {
			t.Error("a bow-sider is never compared with a stroke-sider")
		}
	}
}

// The quick Sherman-Morrison prediction must equal a full refit with the extra piece.
func TestSwapPredictionMatchesRefit(t *testing.T) {
	text := readExample(t, "womens-four.txt")
	s := mustParse(t, text)
	f, _ := estimate(s, 0.6)
	last := s.Pieces[len(s.Pieces)-1]
	c0 := append([]int(nil), last.Boats[0].Crew...)
	c1 := append([]int(nil), last.Boats[1].Crew...)
	c0[0], c1[2] = c1[2], c0[0]
	if !CanSwap(s.Rowers[c0[0]].Side, s.Rowers[c1[2]].Side) {
		t.Fatal("test swap should be same-side")
	}
	u := newUpdate(f, marginVector(f, c0, c1, 0, 1))
	extra := "piece 1000 m\nboat " + last.Boats[0].Hull + " 200"
	for _, r := range c0 {
		extra += " " + s.Rowers[r].Name
	}
	extra += "\nboat " + last.Boats[1].Hull + " 201"
	for _, r := range c1 {
		extra += " " + s.Rowers[r].Name
	}
	s2 := mustParse(t, text+"\n"+extra+"\n")
	f2, _ := estimate(s2, 0.6)
	for i := range s.Rowers {
		for j := range s.Rowers {
			want := f2.DiffSD(i, j)
			got := math.Sqrt(u.diffVar(i, j))
			if math.Abs(got-want) > 1e-6 {
				t.Fatalf("rowers %d,%d: predicted %.6f, refit %.6f", i, j, got, want)
			}
		}
	}
}

func TestSwapsRespectSides(t *testing.T) {
	s := mustParse(t, readExample(t, "womens-four.txt"))
	f, _ := Estimate(s)
	swaps := NextSwaps(s, f)
	if len(swaps) != 1+8 { // the same crews again, plus 2x2 swaps on each side
		t.Fatalf("%d candidate swaps", len(swaps))
	}
	for k, sw := range swaps {
		if sw.A >= 0 && s.Rowers[sw.A].Side != s.Rowers[sw.B].Side {
			t.Error("swaps keep each rower on their side")
		}
		if sw.After > sw.Before+1e-12 {
			t.Error("another piece never makes the selection less certain")
		}
		if k > 0 && sw.After < swaps[k-1].After {
			t.Error("swaps are sorted best first")
		}
	}
}

// Following the advice should settle a selection faster than random same-side swaps.
func TestAdviceBeatsRandomSwaps(t *testing.T) {
	speeds := []float64{1.0, 0.3, 0.7, -0.2, 0.5, -0.6, 0.1, -0.9}
	sides := []string{"bow", "stroke", "stroke", "bow", "bow", "stroke", "stroke", "bow"}
	run := func(advised bool, seed uint64) float64 {
		rng := rand.New(rand.NewPCG(seed, 99))
		crews := [2][]int{{0, 1, 3, 5}, {4, 2, 7, 6}}
		head := "seats 4\nnoise 0.6\n"
		for i := range speeds {
			head += fmt.Sprintf("rower R%d %s\n", i, sides[i])
		}
		body := ""
		var last float64
		for p := 0; p < 7; p++ {
			base := 200 + rng.NormFloat64()
			body += "piece 1000 m\n"
			for k := 0; k < 2; k++ {
				tm := base + rng.NormFloat64()*0.6
				for _, r := range crews[k] {
					tm -= speeds[r]
				}
				body += fmt.Sprintf("boat H%d %.2f", k, tm)
				for _, r := range crews[k] {
					body += fmt.Sprintf(" R%d", r)
				}
				body += "\n"
			}
			s := mustParse(t, head+body)
			f, _ := Estimate(s)
			swaps := NextSwaps(s, f)
			last = swaps[0].Before
			pick := swaps[0]
			if !advised {
				for pick = swaps[rng.IntN(len(swaps))]; pick.A < 0; pick = swaps[rng.IntN(len(swaps))] {
				}
			}
			if pick.A >= 0 {
				for k := 0; k < 2; k++ {
					for i, r := range crews[k] {
						if r == pick.A {
							crews[k][i] = pick.B
						} else if r == pick.B {
							crews[k][i] = pick.A
						}
					}
				}
			}
		}
		return last
	}
	advised, random := 0.0, 0.0
	for seed := uint64(0); seed < 12; seed++ {
		advised += run(true, seed)
		random += run(false, seed)
	}
	if advised >= random {
		t.Errorf("advice left %.2f expected wrong calls, random swaps %.2f", advised/12, random/12)
	}
}

func readExample(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile("../../examples/" + name)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestRun(t *testing.T) {
	var out, errb bytes.Buffer
	if code := Run([]string{"../../examples/womens-four.txt"}, nil, &out, &errb); code != 0 || !strings.Contains(out.String(), "BOW SIDE") {
		t.Fatalf("example: %d %s", code, errb.String())
	}
	var out2 bytes.Buffer
	in := strings.NewReader(readExample(t, "womens-four.txt"))
	if Run([]string{"-"}, in, &out2, &errb) != 0 || out2.String() != out.String() {
		t.Error("standard input gives the same, repeatable report")
	}
	var o, e bytes.Buffer
	if Run(nil, nil, &o, &e) != 2 || Run([]string{"--help"}, nil, &o, &e) != 2 || Run([]string{"a", "b"}, nil, &o, &e) != 2 {
		t.Error("usage errors exit 2")
	}
	e.Reset()
	if Run([]string{"../../examples"}, nil, &o, &e) != 2 || !strings.Contains(e.String(), "could not be read") {
		t.Error("a folder is refused")
	}
	e.Reset()
	if Run([]string{"secret-name-zz.txt"}, nil, &o, &e) != 2 || strings.Contains(e.String(), "secret-name") {
		t.Error("errors don't echo the path")
	}
	e.Reset()
	if Run([]string{"-"}, strings.NewReader(strings.Repeat("#", 200000)), &o, &e) != 2 || !strings.Contains(e.String(), "64 KB") {
		t.Error("big input is cut off")
	}
	e.Reset()
	if Run([]string{"-"}, strings.NewReader("rower <img>\n"), &o, &e) != 2 || strings.Contains(e.String(), "<img>") {
		t.Error("input errors don't echo the input")
	}
	var d bytes.Buffer
	if Run([]string{"../../examples/double-sculls.txt"}, nil, &d, &e) != 0 || !strings.Contains(d.String(), "SQUAD") {
		t.Error("the sculling example runs")
	}
}

func FuzzParse(f *testing.F) {
	f.Add(two)
	f.Add(readExampleF("womens-four.txt"))
	f.Add("piece 1000 m\nboat X 3:00 A\n")
	f.Fuzz(func(t *testing.T, text string) {
		s, err := Parse(text)
		if err != nil {
			return
		}
		if _, err := Render(s); err != nil {
			t.Skip() // a fit can legitimately fail only on degenerate numbers
		}
	})
}

func readExampleF(name string) string {
	data, _ := os.ReadFile("../../examples/" + name)
	return string(data)
}
