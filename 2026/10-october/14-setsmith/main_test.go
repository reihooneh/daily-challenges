package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func cli(args []string, stdin string) (int, string, string) {
	var out, errOut bytes.Buffer
	code := run(args, strings.NewReader(stdin), &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestExampleRuns(t *testing.T) {
	code, out, errOut := cli([]string{"examples/pub-gig.txt"}, "")
	if code != 0 || errOut != "" || !strings.Contains(out, "Northern Line") {
		t.Fatalf("code %d, err %q", code, errOut)
	}
}

func TestStandardInputAndNoPlan(t *testing.T) {
	code, out, _ := cli([]string{"-"}, "slot 10:00\nreserve 0:00\nsong A | 6:00 | must\nsong B | 6:00 | must\n")
	if code != 1 || !strings.Contains(out, "No running order fits") {
		t.Fatalf("code %d:\n%s", code, out)
	}
}

func TestBadArgumentsAndFiles(t *testing.T) {
	dir := t.TempDir()
	big := filepath.Join(dir, "big.txt")
	os.WriteFile(big, bytes.Repeat([]byte("#\n"), 20000), 0o600)
	for _, args := range [][]string{{}, {"a", "b"}, {"--bogus"}, {"/no/such/file"}, {dir}, {big}, {"/dev/zero"},
		{"\x1b]0;owned\a$(reboot)"}} {
		code, out, errOut := cli(args, "")
		if code != 2 || out != "" || !strings.HasPrefix(errOut, "setsmith: ") {
			t.Errorf("%q: code %d, out %q, err %q", args, code, out, errOut)
		}
		if strings.Contains(errOut, "owned") || strings.Contains(errOut, "reboot") {
			t.Errorf("error repeats the argument: %q", errOut)
		}
	}
	if code, _, errOut := cli([]string{"-"}, strings.Repeat("x", 100000)); code != 2 || !strings.Contains(errOut, "16 KB") {
		t.Errorf("huge standard input: %d %q", code, errOut)
	}
}

func TestOddFileNameIsPrintedSafely(t *testing.T) {
	path := filepath.Join(t.TempDir(), "gig\x1b[31m.txt")
	if err := os.WriteFile(path, []byte("slot 30:00\nsong A | 3:00\n"), 0o600); err != nil {
		t.Skip("file system refuses the name")
	}
	code, out, _ := cli([]string{path}, "")
	if code != 0 || strings.ContainsRune(out, 0x1b) || !strings.Contains(out, "gig??31m.txt") {
		t.Errorf("code %d, out %q", code, out)
	}
}
