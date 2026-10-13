// Package setlist plans a band's running order: which songs to play and in what order,
// so the set fits the slot, the energy rises and falls the way a good set should, the
// singer gets a breather, and as little time as possible is lost to retuning.
package setlist

import (
	"bufio"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Limits that keep every input small enough to plan exactly and quickly.
const (
	MaxBytes   = 16 * 1024
	MaxSongs   = 16
	MaxPlayers = 8
	MaxLine    = 300
)

// Priority says how much a song matters.
type Priority int

const (
	Must  Priority = iota // always played
	Want                  // played unless it really can't fit
	Maybe                 // a filler, happy to drop
)

func (p Priority) String() string { return [...]string{"must", "want", "maybe"}[p] }

// Tuning is what one player's instrument needs for one song.
type Tuning struct {
	Name string // "standard", "dropD", "DADGAD", ...
	Capo int    // fret, 0 for none
}

// Song is one entry in the band's list.
type Song struct {
	Title    string
	Secs     int
	Energy   int // 1 (gentle) to 5 (flat out)
	Parts    map[string]Tuning
	Hard     bool // hard on the singer's voice
	Priority Priority
	Opener   bool
	Closer   bool
	Then     string // the song this one runs straight into (a segue)
}

// Gig is the whole input: the slot, the band's habits and the songs.
type Gig struct {
	Slot      int // seconds on stage
	Reserve   int // seconds kept back for talking, tuning and surprises
	Gap       int // seconds between any two songs
	Retune    int // seconds to retune an instrument
	CapoMove  int // seconds to move or remove a capo
	Swap      int // seconds to swap to a spare instrument
	BeltLimit int // most hard songs in a row
	Spares    map[string]map[string]bool
	Songs     []Song
}

// InputError is a problem with the gig file. Its message never repeats the input.
type InputError struct{ Msg string }

func (e *InputError) Error() string { return e.Msg }

func fail(line int, format string, args ...any) error {
	where := ""
	if line > 0 {
		where = fmt.Sprintf("line %d: ", line)
	}
	return &InputError{where + fmt.Sprintf(format, args...)}
}

var (
	titleRe = regexp.MustCompile(`^[\p{L}\p{N}][\p{L}\p{N} '&!?.,()-]{0,39}$`)
	nameRe  = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9#_-]{0,15}$`)
	timeRe  = regexp.MustCompile(`^(\d{1,3}):([0-5]\d)$`)
)

// Clock parses "3:40" into seconds.
func Clock(s string) (int, bool) {
	m := timeRe.FindStringSubmatch(strings.TrimSpace(s))
	if m == nil {
		return 0, false
	}
	min, _ := strconv.Atoi(m[1])
	sec, _ := strconv.Atoi(m[2])
	return min*60 + sec, true
}

// FormatClock turns seconds into "3:40".
func FormatClock(secs int) string {
	sign := ""
	if secs < 0 {
		sign, secs = "-", -secs
	}
	return fmt.Sprintf("%s%d:%02d", sign, secs/60, secs%60)
}

func isPrintable(s string) bool {
	for _, r := range s {
		if r < 0x20 || r == 0x7f || (r >= 0x80 && r < 0xa0) || (r >= 0x200b && r <= 0x200f) ||
			(r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) || r == 0xfeff {
			return false
		}
	}
	return true
}

// Parse reads a gig file. See the README for the format.
func Parse(text string) (*Gig, error) {
	if len(text) > MaxBytes {
		return nil, fail(0, "the file is larger than 16 KB")
	}
	if !isPrintable(strings.NewReplacer("\n", "", "\r", "", "\t", "").Replace(text)) {
		return nil, fail(0, "the file has control or invisible characters")
	}
	g := &Gig{Gap: 20, Retune: 90, CapoMove: 15, Swap: 15, BeltLimit: 2, Reserve: -1,
		Spares: map[string]map[string]bool{}}
	seen := map[string]bool{}
	players := map[string]bool{}
	sc := bufio.NewScanner(strings.NewReader(text))
	sc.Buffer(make([]byte, 0, MaxLine+2), MaxLine+2)
	n := 0
	for sc.Scan() {
		n++
		line := sc.Text()
		if len(line) > MaxLine {
			return nil, fail(n, "the line is longer than %d characters", MaxLine)
		}
		// Comments: a whole line starting with #, or " # " and anything after it
		// (a # inside a word, as in the tuning C#, is kept).
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		if i := strings.Index(line, " # "); i >= 0 {
			line = line[:i]
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		word, rest, _ := strings.Cut(line, " ")
		rest = strings.TrimSpace(rest)
		switch word {
		case "slot", "reserve", "gap", "retune", "capo", "swap":
			secs, ok := Clock(rest)
			limits := map[string][2]int{"slot": {5 * 60, 4 * 3600}, "reserve": {0, 3600}, "gap": {0, 300},
				"retune": {0, 600}, "capo": {0, 300}, "swap": {0, 300}}[word]
			if !ok || secs < limits[0] || secs > limits[1] {
				return nil, fail(n, "%s must be a time like 1:30, from %s to %s", word,
					FormatClock(limits[0]), FormatClock(limits[1]))
			}
			*map[string]*int{"slot": &g.Slot, "reserve": &g.Reserve, "gap": &g.Gap, "retune": &g.Retune,
				"capo": &g.CapoMove, "swap": &g.Swap}[word] = secs
		case "belt-limit":
			v, err := strconv.Atoi(rest)
			if err != nil || v < 1 || v > 4 {
				return nil, fail(n, "belt-limit must be a whole number from 1 to 4")
			}
			g.BeltLimit = v
		case "player":
			f := strings.Fields(rest)
			if len(f) < 1 || !nameRe.MatchString(f[0]) {
				return nil, fail(n, "write a player as: player Name [spare tuning ...]")
			}
			if len(f) > 1 && (f[1] != "spare" || len(f) < 3) {
				return nil, fail(n, "write a player as: player Name [spare tuning ...]")
			}
			players[f[0]] = true
			for _, t := range f[min(2, len(f)):] {
				if !nameRe.MatchString(t) {
					return nil, fail(n, "a tuning name must be letters, digits, # _ or -, up to 16")
				}
				if g.Spares[f[0]] == nil {
					g.Spares[f[0]] = map[string]bool{}
				}
				g.Spares[f[0]][t] = true
			}
		case "song":
			if len(g.Songs) >= MaxSongs {
				return nil, fail(n, "more than %d songs: trim the list to the ones you might play", MaxSongs)
			}
			s, err := parseSong(rest, n)
			if err != nil {
				return nil, err
			}
			key := strings.ToLower(s.Title)
			if seen[key] {
				return nil, fail(n, "two songs have the same title")
			}
			seen[key] = true
			for p := range s.Parts {
				players[p] = true
			}
			g.Songs = append(g.Songs, s)
		default:
			return nil, fail(n, "start the line with song, player, slot, reserve, gap, retune, capo, swap or belt-limit")
		}
	}
	if err := sc.Err(); err != nil {
		return nil, fail(n+1, "the line is longer than %d characters", MaxLine)
	}
	if g.Slot == 0 {
		return nil, fail(0, "the file needs a slot line, like: slot 45:00")
	}
	if len(g.Songs) == 0 {
		return nil, fail(0, "the file has no songs")
	}
	if len(players) > MaxPlayers {
		return nil, fail(0, "more than %d players", MaxPlayers)
	}
	if g.Reserve < 0 {
		g.Reserve = g.Slot / 10
	}
	if g.Reserve >= g.Slot {
		return nil, fail(0, "the reserve leaves no time for music")
	}
	return g, g.check()
}

var flagWords = map[string]bool{"must": true, "want": true, "maybe": true, "hard": true, "opener": true, "closer": true}

func parseSong(rest string, n int) (Song, error) {
	parts := strings.Split(rest, "|")
	if len(parts) < 2 {
		return Song{}, fail(n, "write a song as: song Title | 3:40 | energy 4 | Player tuning, ... | must hard")
	}
	s := Song{Title: strings.TrimSpace(parts[0]), Energy: 3, Priority: Want, Parts: map[string]Tuning{}}
	if !titleRe.MatchString(s.Title) {
		return s, fail(n, "a song title must be 1 to 40 letters, digits, spaces or ' & ! ? . , ( ) -")
	}
	secs, ok := Clock(parts[1])
	if !ok || secs < 30 || secs > 15*60 {
		return s, fail(n, "a song's length must be a time from 0:30 to 15:00")
	}
	s.Secs = secs
	priorities := 0
	for _, seg := range parts[2:] {
		seg = strings.TrimSpace(seg)
		words := strings.Fields(seg)
		switch {
		case seg == "":
		case words[0] == "energy":
			v, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(seg, "energy")))
			if err != nil || v < 1 || v > 5 {
				return s, fail(n, "energy must be a whole number from 1 to 5")
			}
			s.Energy = v
		case words[0] == "then":
			s.Then = strings.TrimSpace(strings.TrimPrefix(seg, "then"))
			if !titleRe.MatchString(s.Then) {
				return s, fail(n, "after 'then', give the title of the next song")
			}
		case allFlags(words):
			for _, w := range words {
				switch w {
				case "must", "want", "maybe":
					s.Priority = map[string]Priority{"must": Must, "want": Want, "maybe": Maybe}[w]
					priorities++
				case "hard":
					s.Hard = true
				case "opener":
					s.Opener = true
				case "closer":
					s.Closer = true
				}
			}
		default:
			for _, part := range strings.Split(seg, ",") {
				f := strings.Fields(part)
				if len(f) != 2 && !(len(f) == 4 && f[2] == "capo") {
					return s, fail(n, "write a part as: Player tuning, or Player tuning capo 2")
				}
				if !nameRe.MatchString(f[0]) || !nameRe.MatchString(f[1]) {
					return s, fail(n, "player and tuning names must be letters, digits, # _ or -, up to 16")
				}
				t := Tuning{Name: f[1]}
				if len(f) == 4 {
					c, err := strconv.Atoi(f[3])
					if err != nil || c < 1 || c > 12 {
						return s, fail(n, "a capo must be on a fret from 1 to 12")
					}
					t.Capo = c
				}
				if _, dup := s.Parts[f[0]]; dup {
					return s, fail(n, "a player is listed twice in one song")
				}
				s.Parts[f[0]] = t
			}
		}
	}
	if priorities > 1 {
		return s, fail(n, "give a song only one of must, want or maybe")
	}
	if s.Opener || s.Closer {
		s.Priority = Must
	}
	return s, nil
}

func allFlags(words []string) bool {
	for _, w := range words {
		if !flagWords[w] {
			return false
		}
	}
	return true
}

// check looks for rules that contradict each other.
func (g *Gig) check() error {
	index := map[string]int{}
	for i, s := range g.Songs {
		index[strings.ToLower(s.Title)] = i
	}
	openers, closers := 0, 0
	into := map[int]int{}
	for i, s := range g.Songs {
		if s.Opener {
			openers++
		}
		if s.Closer {
			closers++
		}
		if s.Then == "" {
			continue
		}
		j, ok := index[strings.ToLower(s.Then)]
		if !ok {
			return fail(0, "%q runs into a song that isn't in the list", s.Title)
		}
		if j == i {
			return fail(0, "%q can't run into itself", s.Title)
		}
		if _, dup := into[j]; dup {
			return fail(0, "two songs run into %q", g.Songs[j].Title)
		}
		into[j] = i
	}
	if openers > 1 || closers > 1 {
		return fail(0, "only one song can be the opener and one the closer")
	}
	// Segue chains must not loop, and must not try to put anything before the opener.
	for i := range g.Songs {
		seen := map[int]bool{}
		for j := i; g.Songs[j].Then != ""; j = index[strings.ToLower(g.Songs[j].Then)] {
			if seen[j] {
				return fail(0, "songs that run into each other form a loop")
			}
			seen[j] = true
		}
		if g.Songs[i].Opener {
			if _, ok := into[i]; ok {
				return fail(0, "the opener can't follow another song")
			}
		}
		if g.Songs[i].Closer && g.Songs[i].Then != "" {
			return fail(0, "the closer can't run into another song")
		}
	}
	return nil
}
