package setlist

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"strings"
	"testing"
	"time"
)

func mustParse(t *testing.T, text string) *Gig {
	t.Helper()
	g, err := Parse(text)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return g
}

func TestClock(t *testing.T) {
	for in, want := range map[string]int{"3:40": 220, "0:05": 5, "45:00": 2700, "120:00": 7200} {
		if got, ok := Clock(in); !ok || got != want {
			t.Errorf("Clock(%q) = %d, %v", in, got, ok)
		}
	}
	for _, bad := range []string{"", "3", "3:6", "3:60", "-1:00", "1:00:00", "1e3:00", "abc"} {
		if _, ok := Clock(bad); ok {
			t.Errorf("Clock(%q) should fail", bad)
		}
	}
	if FormatClock(-75) != "-1:15" || FormatClock(3725) != "62:05" {
		t.Error("FormatClock")
	}
}

func TestParseTheExample(t *testing.T) {
	data, err := os.ReadFile("../examples/pub-gig.txt")
	if err != nil {
		t.Fatal(err)
	}
	g := mustParse(t, string(data))
	if g.Slot != 2700 || g.Reserve != 240 || g.BeltLimit != 2 || len(g.Songs) != 12 {
		t.Fatalf("settings: %+v", g)
	}
	if !g.Spares["Mia"]["dropD"] {
		t.Error("spare guitar not read")
	}
	s := g.Songs[1]
	if s.Title != "Paper Lanterns" || s.Secs != 260 || s.Energy != 2 || s.Parts["Mia"] != (Tuning{"standard", 3}) {
		t.Errorf("song: %+v", s)
	}
	if !g.Songs[0].Opener || g.Songs[0].Priority != Must || g.Songs[6].Then != "Last Stop" {
		t.Error("flags")
	}
}

func TestBadAndHostileFiles(t *testing.T) {
	const ok = "slot 30:00\n"
	cases := map[string]string{
		"":                           "needs a slot line",
		"slot 30:00\n":               "no songs",
		"slot 2:00\nsong A | 3:00\n": "slot must be a time",
		"slot 30:00\nreserve 30:00\nsong A | 3:00\n":            "leaves no time",
		ok + "song A | 3:00 | energy 9\n":                       "energy must be",
		ok + "song A | 0:10\n":                                  "from 0:30 to 15:00",
		ok + "song A | 3:00 | must maybe\n":                     "only one of",
		ok + "song A | 3:00\nsong a | 3:00\n":                   "same title",
		ok + "song A | 3:00 | then B\n":                         "isn't in the list",
		ok + "song A | 3:00 | then A\n":                         "into itself",
		ok + "song A | 3:00 | then B\nsong B | 3:00 | then A\n": "loop",
		ok + "song A | 3:00 | opener\nsong B | 3:00 | opener\n": "only one song can be the opener",
		ok + "song A | 3:00 | Mia standard capo 40\n":           "capo must be",
		ok + "song A | 3:00 | Mia standard, Mia dropD\n":        "listed twice",
		ok + "song <script>alert(1)</script> | 3:00\n":          "song title must be",
		ok + "song A | 3:00 | Mia $(reboot)\n":                  "player and tuning names",
		ok + "belt-limit 99\nsong A | 3:00\n":                   "belt-limit must be",
		ok + "play loud\n":                                      "start the line with",
		ok + "song A\x1b[2J | 3:00\n":                           "control or invisible",
		ok + "song A\u202e | 3:00\n":                            "control or invisible",
		ok + "song A\x00 | 3:00\n":                              "control or invisible",
		ok + strings.Repeat("x", 400) + "\n":                    "longer than 300",
		strings.Repeat("# filler\n", 2000):                      "larger than 16 KB",
	}
	many := ok
	for i := 0; i < 17; i++ {
		many += fmt.Sprintf("song S%d | 3:00\n", i)
	}
	cases[many] = "more than 16 songs"
	for text, want := range cases {
		_, err := Parse(text)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("Parse(%.40q): got %v, want %q", text, err, want)
			continue
		}
		if strings.Contains(err.Error(), "script") || strings.Contains(err.Error(), "reboot") || strings.ContainsRune(err.Error(), 0x1b) {
			t.Errorf("error repeats the input: %v", err)
		}
	}
}

func TestComments(t *testing.T) {
	g := mustParse(t, "# a gig\nslot 30:00   # half an hour\nplayer Mia spare C#std\nsong A | 3:00 | Mia C#std\n")
	if !g.Spares["Mia"]["C#std"] || g.Songs[0].Parts["Mia"].Name != "C#std" {
		t.Error("a # inside a tuning name must be kept")
	}
}

func TestChanges(t *testing.T) {
	g := mustParse(t, "slot 30:00\nretune 1:30\ncapo 0:15\nswap 0:10\nplayer Mia spare dropD\nsong A | 3:00\n")
	std := &Song{Parts: map[string]Tuning{"Mia": {"standard", 0}, "Theo": {"standard", 0}}}
	cases := []struct {
		to   *Song
		secs int
		note string
	}{
		{&Song{Parts: map[string]Tuning{"Mia": {"standard", 0}}}, 0, ""},
		{&Song{Parts: map[string]Tuning{"Mia": {"standard", 2}}}, 15, "puts a capo on fret 2"},
		{&Song{Parts: map[string]Tuning{"Mia": {"dropD", 0}}}, 10, "swaps to the spare in dropD"},
		{&Song{Parts: map[string]Tuning{"Theo": {"dropD", 0}}}, 90, "Theo retunes to dropD"},
		{&Song{Parts: map[string]Tuning{"Mia": {"dropD", 0}, "Theo": {"dropD", 0}}}, 90, "retunes"}, // in parallel: the slowest
		{&Song{Parts: map[string]Tuning{"Sam": {"open", 0}}}, 0, ""},                                // Sam sat out song A
	}
	for _, c := range cases {
		got := g.ChangeBetween(std, c.to)
		if got.Secs != c.secs || (c.note != "" && !strings.Contains(strings.Join(got.Notes, ";"), c.note)) {
			t.Errorf("change to %v: %+v, want %d %q", c.to.Parts, got, c.secs, c.note)
		}
	}
	back := g.ChangeBetween(&Song{Parts: map[string]Tuning{"Mia": {"dropD", 0}}}, std)
	if back.Secs != 10 || !strings.Contains(back.Notes[0], "swaps back") {
		t.Errorf("swap back: %+v", back)
	}
}

func TestTargetEnergyShape(t *testing.T) {
	if TargetEnergy(0) != 4 || math.Abs(TargetEnergy(0.55)-2.8) > 1e-9 || TargetEnergy(1) != 5 || TargetEnergy(7) != 5 {
		t.Error("the arc should open at 4, dip to 2.8 and finish at 5")
	}
}

// bruteForce tries every order of every subset of songs.
func bruteForce(g *Gig) (float64, bool) {
	n := len(g.Songs)
	best, found := math.Inf(1), false
	var order []int
	used := make([]bool, n)
	var walk func()
	walk = func() {
		if len(order) > 0 && g.Valid(order) {
			if s := g.Score(append([]int(nil), order...)).Score; s < best {
				best, found = s, true
			}
		}
		for i := 0; i < n; i++ {
			if !used[i] {
				used[i] = true
				order = append(order, i)
				walk()
				order = order[:len(order)-1]
				used[i] = false
			}
		}
	}
	walk()
	return best, found
}

func randomGig(r *rand.Rand) string {
	tunings := []string{"standard", "dropD", "DADGAD"}
	var b strings.Builder
	fmt.Fprintf(&b, "slot %d:00\nreserve 1:00\ngap 0:%02d\nbelt-limit %d\n", 12+r.Intn(14), 10+r.Intn(30), 1+r.Intn(2))
	if r.Intn(2) == 0 {
		b.WriteString("player Mia spare dropD\n")
	}
	n := 2 + r.Intn(5)
	segue := -1
	if r.Intn(3) == 0 {
		segue = r.Intn(n - 1)
	}
	for i := 0; i < n; i++ {
		fmt.Fprintf(&b, "song S%d | %d:%02d | energy %d | Mia %s", i, 2+r.Intn(4), r.Intn(60), 1+r.Intn(5), tunings[r.Intn(3)])
		if r.Intn(3) == 0 {
			fmt.Fprintf(&b, " capo %d", 1+r.Intn(4))
		}
		fmt.Fprintf(&b, ", Theo %s |", tunings[r.Intn(2)])
		flags := []string{"", "must", "maybe"}[r.Intn(3)]
		if r.Intn(3) == 0 {
			flags += " hard"
		}
		if i == 0 && r.Intn(4) == 0 {
			flags += " opener"
		}
		if i == n-1 && r.Intn(4) == 0 {
			flags += " closer"
		}
		b.WriteString(" " + flags)
		if i == segue {
			fmt.Fprintf(&b, " | then S%d", i+1)
		}
		b.WriteString("\n")
	}
	return b.String()
}

func TestSolveMatchesBruteForce(t *testing.T) {
	r := rand.New(rand.NewSource(14))
	solved, impossible := 0, 0
	for trial := 0; trial < 400; trial++ {
		text := randomGig(r)
		g, err := Parse(text)
		if err != nil {
			t.Fatalf("generated gig did not parse: %v\n%s", err, text)
		}
		want, ok := bruteForce(g)
		plan, err := g.Solve()
		if !ok {
			impossible++
			if err == nil {
				t.Fatalf("Solve found a plan where brute force found none:\n%s", text)
			}
			continue
		}
		solved++
		if err != nil {
			t.Fatalf("Solve found nothing, brute force scored %.2f:\n%s", want, text)
		}
		if math.Abs(plan.Score-want) > 1e-6 || !g.Valid(plan.Order) {
			t.Fatalf("Solve scored %.4f, brute force %.4f:\n%s", plan.Score, want, text)
		}
	}
	if solved < 200 || impossible < 5 {
		t.Errorf("the random gigs should include both kinds: %d solved, %d impossible", solved, impossible)
	}
}

func TestRulesAreKept(t *testing.T) {
	g := mustParse(t, `slot 40:00
reserve 0:00
belt-limit 1
song Opener | 3:00 | energy 5 | opener
song Belter One | 3:00 | energy 5 | hard must
song Belter Two | 3:00 | energy 5 | hard must
song Quiet | 3:00 | energy 1 | must
song Into | 3:00 | energy 4 | then Out
song Out | 3:00 | energy 4
song Finale | 3:00 | energy 5 | closer
`)
	p, err := g.Solve()
	if err != nil {
		t.Fatal(err)
	}
	pos := map[string]int{}
	for k, s := range p.Order {
		pos[g.Songs[s].Title] = k
	}
	if pos["Opener"] != 0 || pos["Finale"] != len(p.Order)-1 {
		t.Errorf("opener and closer: %v", pos)
	}
	if d := pos["Belter One"] - pos["Belter Two"]; d == 1 || d == -1 {
		t.Error("two hard songs in a row with belt-limit 1")
	}
	if in, ok := pos["Into"]; ok && pos["Out"] != in+1 {
		t.Error("a segue was split")
	}
}

func TestNothingFits(t *testing.T) {
	g := mustParse(t, "slot 10:00\nreserve 0:00\nsong A | 6:00 | must\nsong B | 6:00 | must\n")
	_, err := g.Solve()
	if err == nil || !strings.Contains(err.Error(), "must-play songs alone need 12:20") {
		t.Errorf("want a clear reason, got %v", err)
	}
	g = mustParse(t, "slot 40:00\nbelt-limit 1\nsong A | 3:00 | hard must\nsong B | 3:00 | hard must\n")
	if _, err := g.Solve(); err == nil || !strings.Contains(err.Error(), "runs of 1") {
		t.Errorf("want a belt-limit reason, got %v", err)
	}
}

func TestSixteenSongsIsQuick(t *testing.T) {
	var b strings.Builder
	b.WriteString("slot 75:00\nbelt-limit 4\nplayer Mia spare dropD\n")
	for i := 0; i < MaxSongs; i++ {
		fmt.Fprintf(&b, "song Song %d | 4:%02d | energy %d | Mia %s, Theo standard | %s\n", i, i*3, 1+i%5,
			[]string{"standard", "dropD", "DADGAD"}[i%3], []string{"want", "maybe", "hard"}[i%3])
	}
	g := mustParse(t, b.String())
	start := time.Now()
	p, err := g.Solve()
	if err != nil || !g.Valid(p.Order) {
		t.Fatalf("no valid plan: %v", err)
	}
	if took := time.Since(start); took > 10*time.Second {
		t.Errorf("16 songs took %v", took)
	}
}

func TestRender(t *testing.T) {
	data, _ := os.ReadFile("../examples/pub-gig.txt")
	g := mustParse(t, string(data))
	p, err := g.Solve()
	if err != nil {
		t.Fatal(err)
	}
	out := Render(g, p, "pub-gig.txt")
	for _, want := range []string{"SETSMITH  pub-gig.txt", " 1   0:00  Northern Line", "straight into it", "LEFT OUT", "ENERGY", "SCORE"} {
		if !strings.Contains(out, want) {
			t.Errorf("report is missing %q:\n%s", want, out)
		}
	}
	if !strings.HasSuffix(strings.TrimSpace(strings.Split(out, "\n\n")[1]), "(hard on the voice)") {
		t.Error("the closer, Wildfire, should be last and marked hard")
	}
}
