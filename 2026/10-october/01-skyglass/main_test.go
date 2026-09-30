package main

import (
	"bytes"
	"strings"
	"testing"
	"time"
)

var fixedNow = time.Date(2026, 10, 1, 2, 0, 0, 0, time.UTC)

func runCLI(args ...string) (string, string, int) {
	var out, errOut bytes.Buffer
	code := run(args, &out, &errOut, fixedNow)
	return out.String(), errOut.String(), code
}

func TestDefaultIsSydneyToday(t *testing.T) {
	out, _, code := runCLI()
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	for _, want := range []string{"Sydney", "Thu 1 Oct 2026", "UTC+10", "Sunrise", "Day length", "% lit"} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q:\n%s", want, out)
		}
	}
}

func TestDaylightSavingIsApplied(t *testing.T) {
	out, _, _ := runCLI("--date", "2026-10-05")
	if !strings.Contains(out, "UTC+11") {
		t.Errorf("Sydney on 5 Oct should be on daylight saving (UTC+11):\n%s", out)
	}
}

func TestCustomCoordinatesAndPolarNight(t *testing.T) {
	out, _, code := runCLI("--lat", "78", "--lon", "15", "--tz", "Arctic/Longyearbyen", "--date", "2026-12-21", "--no-art")
	if code != 0 || !strings.Contains(out, "polar night") {
		t.Errorf("exit %d, output:\n%s", code, out)
	}
	if strings.Contains(out, "#") {
		t.Error("--no-art should hide the Moon drawing")
	}
}

func TestBadInputGivesHelpfulErrors(t *testing.T) {
	cases := [][]string{
		{"--city", "atlantis"},
		{"--lat", "10"},
		{"--lat", "95", "--lon", "0"},
		{"--date", "01/10/2026"},
		{"--lat", "0", "--lon", "0", "--tz", "Mars/Olympus"},
	}
	for _, args := range cases {
		_, errOut, code := runCLI(args...)
		if code != 2 || !strings.HasPrefix(errOut, "skyglass:") {
			t.Errorf("%v: exit %d, stderr %q", args, code, errOut)
		}
	}
}
