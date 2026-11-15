package hellbox

import (
	"fmt"
	"sort"
	"strings"
)

// Report describes a plan in words, with a picture of how full the case is after each forme.
func Report(c *Case, pages []Page, plan Plan, perForme int, shop map[Glyph]int, shopFor int) string {
	var b strings.Builder
	total := 0
	for _, p := range pages {
		total += size(p)
	}
	fmt.Fprintf(&b, "Hellbox: %d %s, %d letters, set from %s (%d sorts)\n", len(pages), plural(len(pages), "page", "pages"), total, c.Name, sum(c.Count))
	fmt.Fprintf(&b, "The press takes %d %s at a time.\n", perForme, plural(perForme, "page", "pages"))

	if len(plan.Alone) > 0 {
		b.WriteString("\nThese pages can't be set with this case even on their own:\n")
		for _, i := range plan.Alone {
			fmt.Fprintf(&b, "  - %s\n", pages[i].Title)
		}
	}
	if len(plan.Formes) > 0 {
		how := "the fewest possible"
		if !plan.Exact {
			how = fmt.Sprintf("no plan can use fewer than %d", plan.LowerBound)
		}
		what := "Set it"
		if len(plan.Alone) > 0 {
			what = "Set the other pages"
		}
		fmt.Fprintf(&b, "\n%s in %d %s (%s; %d settings tried):\n", what, len(plan.Formes), plural(len(plan.Formes), "forme", "formes"), how, plan.Checks)
	}
	for n, f := range plan.Formes {
		var names []string
		for _, i := range f.Pages {
			names = append(names, pages[i].Title)
		}
		fmt.Fprintf(&b, "\n%d. %s (%d letters)\n", n+1, strings.Join(names, ", "), f.Letters)
		if len(f.Ligatures) > 0 {
			var ls []string
			for _, l := range Ligatures {
				if k := f.Ligatures[l]; k > 0 {
					ls = append(ls, fmt.Sprintf("%s ×%d", Show(l), k))
				}
			}
			fmt.Fprintf(&b, "   Ligatures: %s\n", strings.Join(ls, ", "))
		}
		if len(f.Subs) == 0 {
			b.WriteString("   Every letter is its own sort.\n")
		}
		for _, s := range f.Subs {
			fmt.Fprintf(&b, "   %s ×%d set as %s\n", Show(s.For), s.Count, s.Note)
		}
		if tight := tightest(f.Spare, c, 6); tight != "" {
			fmt.Fprintf(&b, "   Nearly out: %s\n", tight)
		}
	}
	if len(shop) > 0 {
		fmt.Fprintf(&b, "\nTo set it in %d %s instead, buy:\n", shopFor, plural(shopFor, "forme", "formes"))
		for _, g := range sortedGlyphs(shop) {
			fmt.Fprintf(&b, "  %-6s ×%d\n", Show(g), shop[g])
		}
	}
	return b.String()
}

// tightest lists the sorts with the least left, as a share of what the case holds.
func tightest(spare map[Glyph]int, c *Case, n int) string {
	type t struct {
		g    Glyph
		left int
		of   int
	}
	var all []t
	for g, k := range spare {
		if of := c.Count[g]; of > 0 && k*4 < of {
			all = append(all, t{g, k, of})
		}
	}
	sort.Slice(all, func(i, j int) bool {
		if all[i].left*all[j].of != all[j].left*all[i].of {
			return all[i].left*all[j].of < all[j].left*all[i].of
		}
		return all[i].g < all[j].g
	})
	var parts []string
	for i, x := range all {
		if i == n {
			break
		}
		parts = append(parts, fmt.Sprintf("%s %d/%d", Show(x.g), x.left, x.of))
	}
	return strings.Join(parts, ", ")
}

func sum(m map[Glyph]int) int {
	n := 0
	for _, k := range m {
		n += k
	}
	return n
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}
