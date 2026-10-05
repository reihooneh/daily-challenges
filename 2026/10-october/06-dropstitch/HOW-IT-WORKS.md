# How Dropstitch works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

Dropstitch is a tiny **compiler front end** for knitting. It has the same three stages every language tool has:

```
 "K2, *YO, K2tog; rep from * to last 2 sts, K2"
        │
        ▼  tokenizer.ts        split text into tokens
 word(k2) , * word(yo) , word(k2tog) ; word(rep) word(from) * ...
        │
        ▼  parser.ts           build a tree
 [ stitch k×2,
   repeat to-end-minus-2 [ stitch yo, stitch k2tog ],
   stitch k×2 ]
        │
        ▼  evaluate.ts         "knit" it with numbers
 24 stitches in  ──▶  24 stitches out, or the first problem
```

`lint.ts` runs those stages for each row and carries the stitch count from one row to the next.

## 2. File tour

| File | Job |
|---|---|
| `src/stitches.ts` | The dictionary: for each stitch, how many it uses and how many it makes |
| `src/tokenizer.ts` | Text to tokens. The only code that reads raw characters. |
| `src/parser.ts` | Tokens to a tree of instructions |
| `src/evaluate.ts` | Works a row and reports the new count or a problem |
| `src/lint.ts` | Row headers, cast-on, the row-to-row count, the printed report |
| `src/cli.ts` | Command line and safe file reading |
| `src/errors.ts` | The error type and every size limit in one place |
| `tests/` | 30 tests |

### `stitches.ts`: two numbers per stitch
The key insight: for counting, a stitch is just `(uses, makes)`. Knit is (1, 1). A yarn over makes a stitch from nothing: (0, 1). Knit-two-together turns two into one: (2, 1). Add a new stitch to the table and the whole tool understands it.

### `tokenizer.ts`: an allow-list
It walks the text one character at a time. Letters and digits become words, digits alone become numbers, and `, ; * ( ) [ ]` become punctuation tokens. Anything else is an error. Checking "is this character on my list?" (an **allow-list**) is much safer than trying to list everything dangerous (a block-list).

### `parser.ts`: recursive descent
The grammar is small:

```
row    = item ("," item)*
item   = stitch | "*" row ["; rep from *"] clause | "(" row ")" clause
clause = "to end" | "to last N sts" | "N times" | "N more times" | "twice"
```

A **recursive descent parser** has one method per rule (`items`, `item`, `starRepeat`, `groupRepeat`, `repeatClause`), and the methods call each other the way the rules refer to each other. Brackets inside brackets work because `groupRepeat` calls `items`, which can call `groupRepeat` again. A `depth` counter stops that recursion at five levels.

The result is a tree with three kinds of node: `stitch`, `rest` ("knit to last 2") and `repeat`.

### `evaluate.ts`: two needles, two counters
`left` is the stitches still waiting; `right` is what has been made. Each node moves stitches from left to right:

- **stitch:** needs `uses × times` on the left, or it's an error.
- **rest:** takes everything except the stitches to leave.
- **repeat to end:** first work out what one pass of the body uses (`shape`). Then it's division: the stitches to cover must be an exact multiple of that width, otherwise "N left over".

Doing repeats with arithmetic instead of a loop is both the correctness check (does it divide evenly?) and the security feature (a huge repeat count costs nothing).

### `lint.ts`: carrying the count
Starts from "Cast on N", then for each row: parse, evaluate, compare with any claimed `(N sts)`, and pass the result to the next row. If a row is broken, the count carries on from the last good value so that one mistake doesn't produce twenty error messages.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Token | The smallest meaningful piece of text: a word, a number, a comma |
| Abstract syntax tree | The structure of the instructions, with the punctuation thrown away |
| Recursive descent | A parser written as functions that call each other, one per grammar rule |
| Allow-list | Accept only what you know is safe; reject everything else |
| Linter | A tool that finds mistakes without running the real thing |
| ReDoS | A regular expression that takes far too long on a crafted input |
| Prototype pollution | Abusing JavaScript's built-in object properties such as `__proto__` |

### TypeScript features you met here
- **Discriminated unions:** `Node` is `stitch | rest | repeat`, told apart by a `kind` field. Inside `if (node.kind === 'stitch')` the compiler knows exactly which fields exist.
- **`readonly` everywhere:** data can't be changed after it's built.
- **`strict` and `noUncheckedIndexedAccess`:** `tokens[i]` has type `Token | undefined`, so forgetting to check for the end of the list is a compile error.
- **Optional chaining** (`token?.kind`) and **nullish coalescing** (`a ?? b`).
- **`Map` over plain objects** for lookups from user input.
- **Type-only imports** (`import type`), which vanish from the compiled code.
- **ES modules** and Node's built-in test runner.

## 4. Interview questions you might get

**Q: Why write a parser by hand instead of using regular expressions?**
A: The language nests: repeats can contain brackets that contain repeats. Regular expressions can't match nested structure properly, and complex ones risk catastrophic backtracking on hostile input. A recursive descent parser handles nesting naturally, reads each token once, and lets me give precise errors with column numbers.

**Q: A user writes "repeat 999999 times" nested four levels deep. What happens?**
A: Nothing slow. I never loop over repeats. I compute what one pass of the body uses and makes, then multiply, and compare with the stitches available. A "to end" repeat is a division with a remainder check. I also refuse a repeat whose body uses zero stitches, because "to end" would never arrive. There's a test that asserts this finishes in a fraction of a second.

**Q: How do you stop a malicious pattern file from doing harm?**
A: The tokenizer is an allow-list, so control characters and markup never get past the first stage, and I never print rejected characters. All limits live in one object and are enforced before any work is done. The stitch table is a `Map` so JavaScript's inherited property names can't be matched. And the program has no dangerous capabilities to abuse: it only reads one file and prints text.

## 5. Ideas to extend it yourself

1. **Multiple sizes:** support `Cast on 80 (96, 112)` and check every size at once.
2. **Fix suggestions:** when a repeat leaves 2 over, suggest the nearest cast-on numbers that would work.
3. **Stitch map:** draw each row as symbols so you can see increases and decreases line up.
