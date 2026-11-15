package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExamples(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run([]string{"-forme", "2", "../../examples/wood-gothic.txt", "../../examples/gig-posters.txt"}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	for _, want := range []string{"Set it in 4 formes (the fewest possible", "W ×2 set as two Vs kerned together", "To set it in 2 formes instead, buy:"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("missing %q in:\n%s", want, out.String())
		}
	}
	out.Reset()
	if code := run([]string{"../../examples/caslon-12.txt", "../../examples/wedding.txt"}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if !strings.Contains(out.String(), "u ×1 set as a turned n") || !strings.Contains(out.String(), "Ligatures: ff ×1, fi ×2, fl ×1") {
		t.Errorf("unexpected:\n%s", out.String())
	}
}

func TestRefusesLinksFoldersAndBadArguments(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "case.txt")
	if err := os.WriteFile(real, []byte("a 3\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link.txt")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("no symlinks here")
	}
	for _, args := range [][]string{
		{link, real},
		{dir, real},
		{filepath.Join(dir, "missing.txt"), real},
	} {
		var out, errb bytes.Buffer
		if code := run(args, &out, &errb); code != 1 || out.Len() != 0 {
			t.Errorf("%v: exit %d, out %q", args, code, out.String())
		}
	}
	var out, errb bytes.Buffer
	if code := run([]string{"-forme", "99", real, real}, &out, &errb); code != 2 {
		t.Errorf("forme 99 accepted")
	}
	if code := run([]string{real}, &out, &errb); code != 2 {
		t.Errorf("one file accepted")
	}
}
