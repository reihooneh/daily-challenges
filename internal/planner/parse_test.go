package planner

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestParseCoursesAndOptions(t *testing.T) {
	p := mustParse(t, `
# a comment
comp1010 Programming Fundamentals   # trailing comment
  Lecture: Mon 10:00-12:00 + Wed 10-11 | tue 2pm-4pm + THURSDAY 14:00-15:00
  computer lab: Fri 9am-12pm
BIOL-20
  Tutorial: Sat 23:00-24:00
`)
	if len(p.Courses) != 2 || p.Courses[0].Code != "COMP1010" || p.Courses[0].Title != "Programming Fundamentals" {
		t.Fatalf("courses = %+v", p.Courses)
	}
	lecture := p.Courses[0].Components[0]
	if lecture.Name != "Lecture" || len(lecture.Options) != 2 {
		t.Fatalf("lecture = %+v", lecture)
	}
	want := []Meeting{{Day: 1, Start: 14 * 60, End: 16 * 60}, {Day: 3, Start: 14 * 60, End: 15 * 60}}
	for i, m := range lecture.Options[1].Meetings {
		if m != want[i] {
			t.Fatalf("meeting %d = %+v, want %+v", i, m, want[i])
		}
	}
	lab := p.Courses[0].Components[1]
	if lab.Name != "Computer lab" || lab.Options[0].Meetings[0] != (Meeting{Day: 4, Start: 9 * 60, End: 12 * 60}) {
		t.Fatalf("lab = %+v", lab)
	}
	if p.Courses[1].Components[0].Options[0].Meetings[0].End != 24*60 {
		t.Fatal("24:00 should be accepted as the end of the day")
	}
}

func TestParseClockTimes(t *testing.T) {
	good := map[string]int{"9": 540, "09:30": 570, "12am": 0, "12pm": 720, "1pm": 780, "11:59pm": 1439, "24:00": 1440, "0:00": 0}
	for text, want := range good {
		if got, err := parseClock(text, 1); err != nil || got != want {
			t.Errorf("%q = %d, %v; want %d", text, got, err, want)
		}
	}
	for _, text := range []string{"", "25", "24:01", "9:60", "13pm", "0am", "9:5", "nine", "9.30", "-9", "9:00:00", "1e3", "٩"} {
		if _, err := parseClock(text, 1); err == nil {
			t.Errorf("%q should be rejected", text)
		}
	}
}

func TestParseEveryWish(t *testing.T) {
	cases := map[string]string{
		"no classes on Fri":                   "No classes on Fri",
		"No Fridays":                          "No classes on Fri",
		"no tuesdays":                         "No classes on Tue",
		"nothing before 9":                    "Nothing before 09:00",
		"not before 10:30":                    "Nothing before 10:30",
		"nothing after 6pm":                   "Nothing after 18:00",
		"lunch 12:00-14:00 for 45 min":        "A 45-minute break between 12:00 and 14:00",
		"break 11-1pm for 30 minutes":         "A 30-minute break between 11:00 and 13:00",
		"at most 3 days":                      "At most 3 days on campus",
		"at most 1 day on campus":             "At most 1 day on campus",
		"at most 6 hours per day":             "At most 6 hours of class per day",
		"at least 15 min between classes":     "At least 15 minutes between classes",
		"busy Tue 14:00-18:00":                "Busy Tue 14:00-18:00",
		"busy tue 2pm-6pm (Work at the Cafe)": "Busy Tue 14:00-18:00 (Work at the Cafe)",
		"BUSY Wed 9-10 netball":               "Busy Wed 09:00-10:00 (netball)",
	}
	for text, want := range cases {
		wish, err := parseWish(text, 1)
		if err != nil {
			t.Errorf("%q: %v", text, err)
			continue
		}
		if got := wish.Describe(); got != want {
			t.Errorf("%q described as %q, want %q", text, got, want)
		}
	}
}

func TestParseRejectsBadStructure(t *testing.T) {
	cases := map[string]string{
		"":                                          "no courses found",
		"# nothing here":                            "no courses found",
		"Lecture: Mon 10-12":                        "before any course name",
		"COMP1010":                                  "has no class times",
		"COMP1010\n Lecture: Mon 12-10":             "must end after it starts",
		"COMP1010\n Lecture: Mon 10-10":             "must end after it starts",
		"COMP1010\n Lecture: Someday 10-12":         "expected a day",
		"COMP1010\n Lecture: Mon":                   "expected a day",
		"COMP1010\n Lecture: Mon 10":                "expected a time range",
		"COMP1010\n Lecture: Mon 10-12 |":           "expected a day",
		"COMP1010\n Lecture: Mon 10-12 + Mon 11-13": "overlap",
		"COMP1010\n Lecture: Mon 10-12\ncomp1010\n Lecture: Tue 10-12":          "used twice",
		"COMP1010\n Lecture: Mon 10-12\nwish: world peace":                      "wish not understood",
		"COMP1010\n Lecture: Mon 10-12\nwish: at most 0 days":                   "between 1 and 7",
		"COMP1010\n Lecture: Mon 10-12\nwish: at most 9 days":                   "between 1 and 7",
		"COMP1010\n Lecture: Mon 10-12\nwish: lunch 12-13 for 90 min":           "must fit inside",
		"COMP1010\n Lecture: Mon 10-12\nwish: at least 999 min between classes": "between 1 and 240",
		"COMP1010\n Lecture: Mon 10-12\nwish: busy Someday 9-10":                "expected a day",
		"x":     "expected a course code",
		"1COMP": "expected a course code",
	}
	for text, want := range cases {
		_, err := Parse(text)
		if err == nil {
			t.Errorf("%q should be rejected", text)
		} else if !strings.Contains(err.Error(), want) {
			t.Errorf("%q: got %q, want it to mention %q", text, err, want)
		} else if !IsParseError(err) {
			t.Errorf("%q: wrong error type", text)
		}
	}
}

func TestParseEnforcesEveryLimit(t *testing.T) {
	line := func(n int, s string) string { return strings.Repeat(s, n) }
	cases := map[string]string{
		line(MaxInputBytes+1, "x"):                                                          "larger than",
		line(MaxLines+1, "\n"):                                                              "more than 2000 lines",
		"COMP1010 " + line(MaxLineLength, "x"):                                              "longer than 1000 characters",
		"COMP1010 " + line(MaxTitleLength+1, "x") + "\n Lecture: Mon 10-12":                 "title is longer",
		"TOOLONGCODE123":                                                                    "expected a course code",
		"A1\n Lecture: Mon 10-11" + line(MaxOptions, " | Mon 10-11"):                        "at most 30 options",
		"A1\n Lecture: Mon 1-2 + Mon 2-3 + Mon 3-4 + Mon 4-5 + Mon 5-6 + Mon 6-7 + Mon 7-8": "at most 6 meetings",
		"A1\n" + line(MaxComponents+1, " Lecture: Mon 10-11\n"):                             "at most 6 components",
		line(MaxCourses+1, "A1\n Lecture: Mon 10-11\n"):                                     "used twice",
		"A1\n Lecture: Mon 10-11\n" + line(MaxWishes+1, "wish: no Fri\n"):                   "more than 24 wishes",
	}
	for text, want := range cases {
		_, err := Parse(text)
		if err == nil || !strings.Contains(err.Error(), want) {
			shown := text
			if len(shown) > 40 {
				shown = shown[:40] + "..."
			}
			t.Errorf("%q: got %v, want it to mention %q", shown, err, want)
		}
	}
	var many strings.Builder
	for i := 0; i <= MaxCourses; i++ {
		many.WriteString("C" + string(rune('A'+i)) + "\n Lecture: Mon 10-11\n")
	}
	if _, err := Parse(many.String()); err == nil || !strings.Contains(err.Error(), "more than 12 courses") {
		t.Errorf("course limit: %v", err)
	}
}

// Hostile input: the parser must reject it, and the error must never repeat it.
func TestParseRejectsHostileTextWithoutEchoingIt(t *testing.T) {
	attacks := []string{
		"COMP1010 <script>alert(1)</script>\n Lecture: Mon 10-12",
		"COMP1010 <img src=x onerror=alert(1)>\n Lecture: Mon 10-12",
		"COMP1010 \"; DROP TABLE courses;--\n Lecture: Mon 10-12",
		"COMP1010 $(rm -rf ~)\n Lecture: Mon 10-12",
		"COMP1010 `id`\n Lecture: Mon 10-12",
		"COMP1010 {{7*7}}\n Lecture: Mon 10-12",
		"COMP1010 Title\x1b[2J\x1b]0;owned\x07\n Lecture: Mon 10-12",
		"COMP1010 Title\x00\n Lecture: Mon 10-12",
		"COMP1010 Ti‮tle\n Lecture: Mon 10-12",
		"COMP1010 Ti​tle\n Lecture: Mon 10-12",
		"COMP1010\n Lecture: Mon 10-12\nwish: busy Mon 9-10 <b>x</b>",
		"COMP1010\n Lecture: Mon 10-12\nwish: busy Mon 9-10 \x1b[31mred",
		"../../etc/passwd\n Lecture: Mon 10-12",
		"COMP1010\n Lecture: Mon 10-12 | <svg/onload=alert(1)>",
		"COMP1010\n <script>: Mon 10-12",
		"\xff\xfe\n",
	}
	for _, attack := range attacks {
		_, err := Parse(attack)
		if err == nil {
			t.Errorf("accepted: %q", attack)
			continue
		}
		message := err.Error()
		for _, fragment := range []string{"script", "alert", "owned", "DROP", "rm -rf", "\x1b", "\x07", "<", ">", "passwd", "onerror", "{{"} {
			if strings.Contains(message, fragment) {
				t.Errorf("error for %q echoes input: %q", attack, message)
			}
		}
	}
}

func TestRunNeverLeaksUnvalidatedText(t *testing.T) {
	response := Run("COMP1010 Maths & Stats (Adv.): Part 1/2\n Lecture: Mon 10-12\nwish: busy Mon 9-11 Dr. O'Neil's lab\n")
	if response.Status != StatusImpossible {
		t.Fatalf("status = %s (%s)", response.Status, response.Error)
	}
	encoded, _ := json.Marshal(response)
	if !strings.Contains(string(encoded), `Dr. O'Neil's lab`) || !strings.Contains(string(encoded), `Stats (Adv.): Part 1/2`) {
		t.Fatalf("legitimate punctuation was lost: %s", encoded)
	}
}

func TestRunReportsErrorsAsData(t *testing.T) {
	response := Run("nonsense line ?!")
	if response.Status != StatusError || response.Error == "" || response.Plan != nil {
		t.Fatalf("%+v", response)
	}
}

// FuzzRun feeds arbitrary bytes through the whole pipeline. Whatever the
// input, Run must return normally with one of the four statuses, and any
// timetable it returns must be free of clashes.
func FuzzRun(f *testing.F) {
	f.Add("COMP1010 Programming\n Lecture: Mon 10:00-12:00 | Tue 14-16\nwish: no Fri\n")
	f.Add("A1\n L: Mon 9-10\nB2\n L: Mon 9-10\nwish: at most 1 days\nwish: lunch 12-14 for 30 min")
	f.Add("wish: busy Mon 9-10 (x)\n\x00\xff")
	f.Add(strings.Repeat("A1\n Lecture: Mon 10-11 | Tue 10-11\n", 3))
	f.Fuzz(func(t *testing.T, text string) {
		response := Run(text)
		switch response.Status {
		case StatusOK:
			for i, a := range response.Plan.Classes {
				for _, b := range response.Plan.Classes[i+1:] {
					if a.Day == b.Day && a.Start < b.End && b.Start < a.End {
						t.Fatalf("clash in returned timetable: %+v and %+v", a, b)
					}
				}
			}
		case StatusImpossible, StatusError, StatusUnknown:
		default:
			t.Fatalf("unexpected status %q", response.Status)
		}
		if _, err := json.Marshal(response); err != nil {
			t.Fatal(err)
		}
	})
}
