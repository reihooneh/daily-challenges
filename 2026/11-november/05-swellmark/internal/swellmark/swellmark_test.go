package swellmark

import (
	"bytes"
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func near(a, b, tol float64) bool { return math.Abs(a-b) <= tol }

// ---------- Wood ----------

func TestEMCMatchesTheWoodHandbook(t *testing.T) {
	// Equilibrium moisture contents from the Wood Handbook's table at about 21 °C.
	for _, c := range []struct{ rh, want float64 }{{30, 6.2}, {50, 9.2}, {65, 12.0}, {80, 16.0}} {
		if got := EMC(c.rh, 21); !near(got, c.want, 0.25) {
			t.Errorf("EMC(%g %%) = %.2f, want about %.1f", c.rh, got, c.want)
		}
	}
	for rh := 6.0; rh < 95; rh++ {
		if EMC(rh+1, 20) <= EMC(rh, 20) {
			t.Fatalf("damper air must mean wetter wood (at %g %%)", rh)
		}
		if EMC(rh, 35) >= EMC(rh, 5) {
			t.Fatalf("warmer air holds wood drier at the same humidity (at %g %%)", rh)
		}
	}
}

func TestCoefficientFollowsTheCut(t *testing.T) {
	cherry := builtinSpecies[3]
	flat := &Part{Species: cherry, Cut: Flat, Grain: 'x', Width: 'y'}
	quarter := &Part{Species: cherry, Cut: Quarter, Grain: 'x', Width: 'y'}
	rift := &Part{Species: cherry, Cut: Rift, Grain: 'x', Width: 'y'}
	checks := []struct {
		got, want float64
		what      string
	}{
		{flat.Coefficient('x'), Longitudinal, "along the grain"},
		{flat.Coefficient('y'), cherry.Tangential, "a flat-sawn board's width moves tangentially"},
		{flat.Coefficient('z'), cherry.Radial, "and its thickness radially"},
		{quarter.Coefficient('y'), cherry.Radial, "a quarter-sawn board's width moves radially"},
		{quarter.Coefficient('z'), cherry.Tangential, "and its thickness tangentially"},
		{rift.Coefficient('y'), (cherry.Radial + cherry.Tangential) / 2, "rift sawn is between"},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s: got %g, want %g", c.what, c.got, c.want)
		}
	}
}

// ---------- Joints ----------

func design(t *testing.T, joints string) *Design {
	t.Helper()
	d, err := Parse("climate 30 to 65\nbuilt-at 45\n" +
		"part top cherry flat grain x width y\n" +
		"part end cherry flat grain y width x\n" +
		"part rail cherry flat grain x width z\n" +
		"part panel walnut flat grain z width x\n" + joints)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return d
}

func TestABreadboardEndWorkedByHand(t *testing.T) {
	d := design(t, "joint top end glue along y 450\n")
	r := Check(d)[0]
	// The top's width (tangential) against the end's length (longitudinal), over half of 450 mm.
	want := (0.00248 - Longitudinal) * 225 * (EMC(65, 20) - EMC(45, 20))
	if !near(r.Damp, want, 1e-9) || !near(r.Need, want, 1e-9) || !r.Damper {
		t.Fatalf("damp movement %.4f, want %.4f (need %.4f)", r.Damp, want, r.Need)
	}
	if r.Dry >= 0 || r.Verdict != Fail {
		t.Fatalf("the top shrinks in the dry season (%.3f) and the glued joint fails (%v)", r.Dry, r.Verdict)
	}
}

func TestLongGrainToLongGrainNeverMoves(t *testing.T) {
	r := Check(design(t, "joint top rail glue along x 2000\n"))[0]
	if r.Need > 1e-12 || r.Verdict != OK {
		t.Fatalf("matching grain should not move: %+v", r)
	}
}

func TestSlidingThresholds(t *testing.T) {
	need := Check(design(t, "joint top end slots 10 along y 450\n"))[0].Need // about 1.92 mm
	for _, c := range []struct {
		allow float64
		want  Verdict
	}{{need / 0.7, OK}, {need / 0.9, Watch}, {need * 0.9, Fail}} {
		d := design(t, "joint top end slots 1 along y 450\n")
		d.Joints[0].Allow = c.allow
		if got := Check(d)[0].Verdict; got != c.want {
			t.Errorf("travel %.2f for %.2f needed: %v, want %v", c.allow, need, got, c.want)
		}
	}
}

func TestFixedAtOneEndDoublesTheTravel(t *testing.T) {
	mid := Check(design(t, "joint top end screws along y 300\n"))[0].Need
	end := Check(design(t, "joint top end screws along y 300 from-end\n"))[0].Need
	if !near(end, 2*mid, 1e-9) {
		t.Fatalf("from one end %.3f, from the middle %.3f", end, mid)
	}
}

func TestFloatingPanel(t *testing.T) {
	// A 400 mm walnut panel grows about 3.8 mm in the damp season and shrinks about 2.5 mm in the dry.
	ok := Check(design(t, "joint panel rail floating 6 depth 10 along x 400\n"))[0]
	if ok.Verdict != OK || !near(ok.Engaged, 10-3-ok.Dry*-0.5, 1e-9) {
		t.Fatalf("a 6 mm gap and 10 mm grooves are fine: %+v", ok)
	}
	tight := Check(design(t, "joint panel rail floating 3 depth 10 along x 400\n"))[0]
	if tight.Verdict != Fail || !tight.Damper {
		t.Fatalf("a 3 mm gap is pushed apart in the damp season: %+v", tight)
	}
	shallow := Check(design(t, "joint panel rail floating 6 depth 5 along x 400\n"))[0]
	if shallow.Verdict != Fail || shallow.Damper || shallow.Engaged >= MinEngagement {
		t.Fatalf("5 mm grooves let it shrink out in the dry season: %+v", shallow)
	}
}

func TestBuiltAtTheDampestOnlyShrinks(t *testing.T) {
	d := design(t, "joint top end glue along y 450\n")
	d.Built = d.High
	r := Check(d)[0]
	if r.Damp != 0 || r.Dry >= 0 || r.Damper {
		t.Fatalf("built in the damp season it can only shrink: %+v", r)
	}
}

// Swapping the two parts of a joint flips the signs and changes nothing else; widening the year's
// humidity never makes a joint safer.
func TestProperties(t *testing.T) {
	rng := rand.New(rand.NewSource(5))
	axes := []byte("xyz")
	for i := 0; i < 2000; i++ {
		part := func() *Part {
			g := axes[rng.Intn(3)]
			w := axes[(int(g-'x')+1+rng.Intn(2))%3]
			return &Part{Species: builtinSpecies[rng.Intn(len(builtinSpecies))], Cut: Cut(rng.Intn(3)), Grain: g, Width: w}
		}
		a, b := part(), part()
		kind := Kind(rng.Intn(3))
		j := Joint{A: a, B: b, Kind: kind, Allow: 1 + 5*rng.Float64(), Depth: 12, Axis: axes[rng.Intn(3)], Extent: 50 + 800*rng.Float64()}
		low := 20 + 20*rng.Float64()
		d := &Design{Low: low, High: low + 10 + 30*rng.Float64(), TempC: 20, RigidLimit: 0.35}
		d.Built = d.Low + (d.High-d.Low)*rng.Float64()
		m := MoistureAt(d, d.Built)
		r := CheckJoint(d, &j, m)
		if kind != Floating {
			swapped := j
			swapped.A, swapped.B = b, a
			s := CheckJoint(d, &swapped, m)
			if !near(s.Damp, -r.Damp, 1e-12) || !near(s.Need, r.Need, 1e-12) || s.Verdict != r.Verdict {
				t.Fatalf("swapping parts changed the result: %+v vs %+v", r, s)
			}
		}
		wider := *d
		wider.Low, wider.High = d.Low-5, d.High+5
		if w := CheckJoint(&wider, &j, MoistureAt(&wider, d.Built)); w.Verdict < r.Verdict {
			t.Fatalf("a wider year made a joint safer: %v then %v", r.Verdict, w.Verdict)
		}
	}
}

func TestBuildWindows(t *testing.T) {
	d := design(t, "joint top end slots 3 along y 450\njoint panel rail floating 6 depth 10 along x 400\n")
	safe, comfortable := BuildWindows(d)
	if len(safe) != 1 || len(comfortable) != 1 || safe[0].From > 45 || safe[0].To < 45 ||
		comfortable[0].From < safe[0].From || comfortable[0].To > safe[0].To {
		t.Fatalf("safe %v, comfortable %v", safe, comfortable)
	}
	if s, _ := BuildWindows(design(t, "joint top end glue along y 450\n")); len(s) != 0 {
		t.Fatalf("a wide glued breadboard end fails at any humidity: %v", s)
	}
}

// ---------- The design file ----------

func TestCustomSpecies(t *testing.T) {
	d, err := Parse("climate 30 to 60\nbuilt-at 45\nspecies sapele radial 0.0017 tangential 0.0024\n" +
		"part a sapele flat grain x width y\npart b sapele flat grain y width x\njoint a b glue along y 100\n")
	if err != nil || d.Parts[0].Species.Tangential != 0.0024 {
		t.Fatalf("custom species: %v", err)
	}
}

func TestRejects(t *testing.T) {
	head := "climate 30 to 65\nbuilt-at 45\npart a cherry flat grain x width y\npart b cherry flat grain y width x\n"
	cases := []struct{ text, want string }{
		{"", "climate"},
		{"climate 30 to 65\n", "built-at"},
		{head, "no joints"},
		{"climate 65 to 30\n", "above the lowest"},
		{"climate 2 to 65\n", "from 5 to 95"},
		{"climate 30 to 65\nclimate 30 to 65\n", "only appear once"},
		{"temperature 1e9\n", "a number like"},
		{"built-at -5\n", "a number like"},
		{"built-at 0x41\n", "a number like"},
		{head + "part a cherry flat grain x width y\n", "different"},
		{head + "part c ebony flat grain x width y\n", "unknown species"},
		{head + "part c cherry flat grain x width x\n", "different directions"},
		{head + "part c cherry sliced grain x width y\n", "flat, quarter or rift"},
		{head + "part C cherry flat grain x width y\n", "lower-case"},
		{head + "joint a c glue along y 100\n", "earlier part lines"},
		{head + "joint a a glue along y 100\n", "two different parts"},
		{head + "joint a b welds along y 100\n", "fastenings are"},
		{head + "joint a b glue along w 100\n", "x, y or z"},
		{head + "joint a b glue along y 9000\n", "from 1 to 5000"},
		{head + "joint a b floating 8 depth 3 along y 100\n", "deeper than half"},
		{head + "joint a b floating 4 depth 10 along y 100 from-end\n", "not for floating"},
		{head + "joint a b glue along y 100 sideways\n", "from-end"},
		{head + "species cherry radial 0.001 tangential 0.002\n", "before the parts"},
		{"design <script>alert(1)</script>\n", "design's name"},
		{"design Table\u202eSECRET\n", "invisible formatting"},
		{"design Table\x1b[2J\n", "control"},
		{"design Table\xff\n", "UTF-8"},
		{"rm -rf SECRET\n", "lines are design"},
		{"# " + strings.Repeat("x", 300) + "\n", "longer than 200"},
		{strings.Repeat("#\n", 40000), "larger than 64 KB"},
	}
	for _, c := range cases {
		_, err := Parse(c.text)
		if err == nil {
			t.Errorf("should reject (%s)", c.want)
			continue
		}
		if !strings.Contains(err.Error(), c.want) || strings.Contains(err.Error(), "SECRET") || strings.Contains(err.Error(), "<script") {
			t.Errorf("message %q should mention %q and never repeat the input", err, c.want)
		}
	}
	var many strings.Builder
	many.WriteString("climate 30 to 65\nbuilt-at 45\n")
	for i := 0; i <= MaxParts; i++ {
		many.WriteString("part p" + strings.Repeat("a", i%20) + string(rune('a'+i%26)) + string(rune('a'+i/26)) + " cherry flat grain x width y\n")
	}
	if _, err := Parse(many.String()); err == nil || !strings.Contains(err.Error(), "at most") {
		t.Errorf("too many parts: %v", err)
	}
}

func FuzzParse(f *testing.F) {
	for _, name := range []string{"hall-table.txt", "hall-table-fixed.txt"} {
		if b, err := os.ReadFile(filepath.Join("..", "..", "examples", name)); err == nil {
			f.Add(string(b))
		}
	}
	f.Fuzz(func(t *testing.T, text string) {
		if d, err := Parse(text); err == nil {
			_ = Render(d)
		}
	})
}

// ---------- The command line ----------

func run(args []string, stdin string) (int, string, string) {
	var out, errb bytes.Buffer
	code := Run(args, strings.NewReader(stdin), &out, &errb)
	return code, out.String(), errb.String()
}

func TestCommandLine(t *testing.T) {
	ex := filepath.Join("..", "..", "examples")
	code, out, _ := run([]string{filepath.Join(ex, "hall-table.txt")}, "")
	if code != 1 || !strings.Contains(out, "In all: 2 OK, 2 to watch, 2 failing.") || !strings.Contains(out, "the design itself has to change") {
		t.Fatalf("the example with mistakes: exit %d\n%s", code, out)
	}
	code, out, _ = run([]string{filepath.Join(ex, "hall-table-fixed.txt")}, "")
	if code != 0 || !strings.Contains(out, "6 OK, 0 to watch, 0 failing") || !strings.Contains(out, "Building at 33–63 % humidity") {
		t.Fatalf("the fixed example: exit %d\n%s", code, out)
	}
	text, _ := os.ReadFile(filepath.Join(ex, "hall-table-fixed.txt"))
	if code2, out2, _ := run([]string{"-"}, string(text)); code2 != 0 || out2 != out {
		t.Fatalf("standard input should give the same report")
	}
	if code, _, e := run([]string{ex}, ""); code != 2 || !strings.Contains(e, "regular file") {
		t.Fatalf("a folder is refused: %d %s", code, e)
	}
	if code, _, e := run([]string{"secret-name-zz.txt"}, ""); code != 2 || strings.Contains(e, "secret-name") {
		t.Fatalf("the path isn't echoed: %s", e)
	}
	link := filepath.Join(t.TempDir(), "link.txt")
	abs, _ := filepath.Abs(filepath.Join(ex, "hall-table.txt"))
	if err := os.Symlink(abs, link); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := run([]string{link}, ""); code != 2 {
		t.Fatalf("a symbolic link is refused")
	}
	if code, _, e := run([]string{"-"}, strings.Repeat("#", 100000)); code != 2 || !strings.Contains(e, "64 KB") {
		t.Fatalf("big input: %d %s", code, e)
	}
	if code, _, _ := run(nil, ""); code != 2 {
		t.Fatalf("usage")
	}
	if code, _, _ := run([]string{"a", "b"}, ""); code != 2 {
		t.Fatalf("usage")
	}
}
