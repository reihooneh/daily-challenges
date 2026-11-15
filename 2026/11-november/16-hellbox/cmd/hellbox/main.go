// hellbox: plan a letterpress job around the type you own.
//
//	hellbox [-forme N] [-subs FILE] [-no-subs] CASE JOB
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/reihooneh/daily-challenges/hellbox/internal/hellbox"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("hellbox", flag.ContinueOnError)
	fs.SetOutput(stderr)
	per := fs.Int("forme", 2, "pages that fit on the press at once (1–16)")
	subsFile := fs.String("subs", "", "a file of extra substitutions")
	noSubs := fs.Bool("no-subs", false, "don't use any substitutions")
	fs.Usage = func() {
		fmt.Fprintln(stderr, "usage: hellbox [-forme N] [-subs FILE] [-no-subs] CASE JOB")
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() != 2 || *per < 1 || *per > 16 {
		fs.Usage()
		return 2
	}
	caseText, err := readFile(fs.Arg(0))
	if err != nil {
		fmt.Fprintln(stderr, "hellbox: the case file:", err)
		return 1
	}
	jobText, err := readFile(fs.Arg(1))
	if err != nil {
		fmt.Fprintln(stderr, "hellbox: the job file:", err)
		return 1
	}
	c, err := hellbox.ParseCase("case", caseText)
	if err != nil {
		fmt.Fprintln(stderr, "hellbox:", err)
		return 1
	}
	pages, err := hellbox.ParseJob("job", jobText)
	if err != nil {
		fmt.Fprintln(stderr, "hellbox:", err)
		return 1
	}
	subs := hellbox.DefaultSubs()
	if *noSubs {
		subs = nil
	}
	if *subsFile != "" {
		t, err := readFile(*subsFile)
		if err != nil {
			fmt.Fprintln(stderr, "hellbox: the substitutions file:", err)
			return 1
		}
		more, err := hellbox.ParseSubs("substitutions", t)
		if err != nil {
			fmt.Fprintln(stderr, "hellbox:", err)
			return 1
		}
		subs = append(subs, more...)
	}
	plan := hellbox.PlanJob(c, subs, pages, *per)
	fewest := (len(pages) + *per - 1) / *per
	var shop map[hellbox.Glyph]int
	if len(plan.Alone) > 0 || len(plan.Formes) > fewest {
		shop = hellbox.Shopping(c, subs, pages, *per, fewest)
	}
	fmt.Fprint(stdout, hellbox.Report(c, pages, plan, *per, shop, fewest))
	return 0
}

// readFile reads a plain file of at most 256 KB; links, folders and devices are refused.
func readFile(path string) (string, error) {
	info, err := os.Lstat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", errors.New("not found")
		}
		return "", errors.New("can't be read")
	}
	if !info.Mode().IsRegular() {
		return "", errors.New("must be a plain file")
	}
	if info.Size() > hellbox.MaxFileBytes {
		return "", errors.New("larger than 256 KB")
	}
	f, err := os.Open(path)
	if err != nil {
		return "", errors.New("can't be read")
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, hellbox.MaxFileBytes+1))
	if err != nil || len(b) > hellbox.MaxFileBytes {
		return "", errors.New("can't be read")
	}
	return string(b), nil
}
