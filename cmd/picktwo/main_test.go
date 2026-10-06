package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/reihooneh/pick-two/internal/planner"
)

func runCLI(stdin string, args ...string) (code int, stdout, stderr string) {
	var out, err bytes.Buffer
	code = run(args, strings.NewReader(stdin), &out, &err)
	return code, out.String(), err.String()
}

func TestExitCodes(t *testing.T) {
	if code, out, _ := runCLI("", "../../examples/first-year.txt"); code != 0 || !strings.Contains(out, "A timetable exists") {
		t.Fatalf("feasible: code=%d out=%q", code, out)
	}
	if code, out, _ := runCLI("", "../../examples/the-friday-problem.txt"); code != 1 || !strings.Contains(out, "Ways out") {
		t.Fatalf("impossible: code=%d", code)
	}
	if code, _, errOut := runCLI("?!", "-"); code != 2 || !strings.HasPrefix(errOut, "picktwo: line 1:") {
		t.Fatalf("bad input: code=%d err=%q", code, errOut)
	}
	if code, out, _ := runCLI("", "--help"); code != 0 || !strings.Contains(out, "Usage") {
		t.Fatal("help")
	}
	for _, args := range [][]string{{}, {"a", "b"}, {"--json"}} {
		if code, _, errOut := runCLI("", args...); code != 2 || !strings.Contains(errOut, "Usage") {
			t.Fatalf("%v: code=%d", args, code)
		}
	}
}

func TestJSONOutput(t *testing.T) {
	code, out, _ := runCLI("A1\n Lecture: Mon 10-12\n", "--json", "-")
	var response planner.Response
	if err := json.Unmarshal([]byte(out), &response); err != nil || code != 0 || response.Status != planner.StatusOK {
		t.Fatalf("code=%d err=%v out=%s", code, err, out)
	}
}

func TestUnreadableInputs(t *testing.T) {
	dir := t.TempDir()
	big := filepath.Join(dir, "big.txt")
	if err := os.WriteFile(big, bytes.Repeat([]byte("x"), planner.MaxInputBytes+5), 0o600); err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{
		"/no/such/file":        "cannot read that file",
		dir:                    "cannot read that file",
		"/dev/zero":            "cannot read that file",
		"../../../etc/shadow/": "cannot read that file",
		"a\x00b":               "cannot read that file",
		big:                    "larger than",
	}
	for path, want := range cases {
		code, out, errOut := runCLI("", path)
		if code != 2 || out != "" || !strings.Contains(errOut, want) || strings.Count(errOut, "\n") != 1 {
			t.Errorf("%q: code=%d out=%q err=%q", path, code, out, errOut)
		}
	}
	if code, _, errOut := runCLI(strings.Repeat("y", planner.MaxInputBytes*3), "-"); code != 2 || !strings.Contains(errOut, "larger than") {
		t.Errorf("large stdin: code=%d err=%q", code, errOut)
	}
}
