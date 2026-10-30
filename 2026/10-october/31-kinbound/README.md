# Kinbound

**Works out the earliest and latest possible birth and death years for everyone in a family tree, from baptisms, burials, census ages and marriages. When the records contradict each other, it shows exactly which ones can't all be true and the fewest that would have to be wrong.**

Language: Rust (no dependencies) · Field: genealogy / difference constraints · Day: 31 October 2026

Family history is mostly ranges. A census says Mary was 25 in 1841, another says 36 in 1851, a baptism gives a year but not a birth, and a great-grandmother has no records at all. Each fact limits the others: a mother is roughly 14 to 50 at a birth, a father can die before a birth but not long before, and nobody marries as a baby. Family-tree programs warn about single rules ("mother too old"), but they don't combine *every* record at once, and they can't say which record is the mistake. Kinbound does both:

- **Tightest ranges for everyone:** every record becomes an inequality between years, and shortest paths give the earliest and latest year each birth and death could be. Two census ages that disagree by a year pin Mary to 1815 exactly.
- **People with no records still get dates:** Hannah, Mary's mother, has no records of her own yet, but she must have been born 1765–1801 and died after 1815.
- **Conflicts explained as a chain:** when records can't all be true, it prints the exact chain of facts that clash and by how many years ("they miss by 2 years").
- **The fewest mistakes:** it finds every smallest set of records that, if wrong, removes *every* conflict, so you know which certificates to order first. It then shows the dates for the fix that changes the rest of the tree least.
- **`--why`:** the reasons behind any person's four bounds, line by line.
- **Your rules:** `rule mother-age 16 45`, `rule lifespan 95` and so on, for a family or period where the defaults don't fit.

## Quick start

```bash
cargo run --release -- examples/ashworth.txt
cargo run --release -- examples/ashworth.txt --why hannah
cargo test                                # 17 tests, including a brute-force check
cargo clippy --all-targets -- -D warnings
```

```
KINBOUND  The Ashworth family
8 people, 24 records.
Some records can't all be true.

CONFLICT 1: these can't all hold (they miss by 2 years)
    line 17   Thomas Ashworth was buried in 1858, so died 1857-1858
    line 40   Thomas Ashworth is Sarah Ashworth's father, so died no more than a year before the birth
    line 41   Sarah Ashworth was born in 1861

Fewest records that would have to be wrong: one record. Any of these would explain every conflict:
  - line 17
      Thomas Ashworth was buried in 1858, so died 1857-1858
  - line 40
      Thomas Ashworth is Sarah Ashworth's father, so died no more than a year before the birth
  - line 41
      Sarah Ashworth was born in 1861

The dates below assume line 40 is the mistake: of these, it changes the other dates least.

Person            Born          Died
Thomas Ashworth   1810-1812     1857-1858
Mary Ashworth     1815          1877-1881
John Ashworth     1836          1836-1941
Ellen Ashworth    1839-1840     1839-1945
William Ashworth  1842-1844     1842-1949
George Ashworth   1848-1852     1901-1957
Sarah Ashworth    1861          1861-1966
Hannah Pell       1765-1801     1815-1906

Widest birth ranges, where a new record would help most: Hannah Pell (37 years).
```

So Sarah, born three years after Thomas was buried, is most likely not Thomas's daughter, or the family Bible has her year wrong. And `--why hannah` shows where Hannah's range comes from:

```
Hannah Pell born no earlier than 1765, because:
    line 19   Hannah Pell is Mary Ashworth's mother, and a mother is 14 to 50 at a birth (rule: mother-age)
    line 15   Mary Ashworth was 25 in the 1841 census, so born 1815-1816
```

## The family file

```
name The Ashworth family
person mary Mary Ashworth            # an id, then the name
born mary 1815                       # or: about 1815, 1814-1816, before 1820, after 1810
died mary about 1879
baptised mary 1815                   # born in that year or up to 2 years before
buried mary 1879                     # died in that year or the one before
census mary 1841 age 25              # born 1815 or 1816
alive mary 1860                      # any record showing she was alive: a will, a letter
mother hannah of mary
father thomas of john
married thomas mary 1835
rule mother-age 14 50                # the defaults: mother 14-50, father 15-80,
rule lifespan 105                    # lifespan 105, marriage-age 14
```

"About" means two years either side; "before" and "after" include the year given. Exit codes: `0` every record fits, `1` conflicts found, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 64 KB (read with a hard limit, so an endless stream is cut off), 200 characters a line, 400 people and 1,500 records. Only regular files are opened, and the path is never echoed back.
- **Strict parsing:** every line must match one of a fixed set of shapes, years must be 1000–2100 and ages 0–120. Errors name the line number and what was expected, never the input itself.
- **Safe names in the terminal:** names may use letters in any script, digits and `' . , ( ) -`. Control characters (terminal escapes) and Unicode direction overrides, which could reorder the report, are refused.
- **Bounded work:** Bellman-Ford is O(people × records). The search for the fewest mistakes looks at no more than 3 records at a time and stops after 4,000 consistency checks, and the report says so if it stopped early.
- **Memory-safe code:** Rust with `unsafe` forbidden, overflow checks on in release builds, no dependencies, and `cargo clippy -D warnings` clean (the library is also clean under `clippy::pedantic`).

**Known limits:** the age rules are rules of thumb, and real families break them (adoptions, step-parents, remarriage, a very young or old parent). That's why a conflict is reported as "these records can't all be true", not as an error, and why the rules can be changed. Ages in some early censuses were rounded (the 1841 census in England and Wales rounded adults down to five years), so use `born ... 1820-1825`-style ranges for those. Kinbound works in whole years.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
