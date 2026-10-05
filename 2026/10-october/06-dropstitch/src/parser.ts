// Step 2: turn tokens into a small tree of instructions.
//
// There are only three kinds of instruction:
//   stitch  "K2", "YO", "k2tog"            a known stitch, done n times
//   rest    "knit to last 2 sts", "purl"   one stitch repeated over what is left
//   repeat  "*YO, K2tog; rep from * to end", "(K1, P1) 3 times"
//
// This is a hand-written recursive descent parser: one function per grammar
// rule, each consuming tokens from left to right.

import { LIMITS, PatternError } from './errors.js';
import { ALIASES, STITCHES, type Stitch } from './stitches.js';
import type { Token } from './tokenizer.js';

export type Node =
  | { readonly kind: 'stitch'; readonly name: string; readonly stitch: Stitch; readonly times: number }
  | { readonly kind: 'rest'; readonly name: string; readonly stitch: Stitch; readonly leave: number }
  | { readonly kind: 'repeat'; readonly body: readonly Node[]; readonly mode: RepeatMode };

export type RepeatMode =
  | { readonly type: 'times'; readonly times: number }
  | { readonly type: 'toEnd'; readonly leave: number };

export interface ParsedRow {
  readonly nodes: readonly Node[];
  /** The count the pattern claims, from a trailing "(22 sts)", if present. */
  readonly declared: number | null;
}

const FILLER = new Set(['st', 'sts', 'stitch', 'stitches']);
const NUMBER_WORDS = new Map([['once', 1], ['twice', 2]]);

class Parser {
  private position = 0;

  constructor(private readonly tokens: readonly Token[]) {}

  parseRow(): ParsedRow {
    const declared = this.takeDeclaredCount();
    const nodes = this.items(0, false);
    if (this.position < this.tokens.length) throw this.unexpected();
    if (nodes.length === 0) throw new PatternError('no instructions found');
    return { nodes, declared };
  }

  /** Removes a trailing "( 22 sts )" from the token list and returns the number. */
  private takeDeclaredCount(): number | null {
    const t = this.tokens;
    const n = t.length;
    const [open, count, word, close] = [t[n - 4], t[n - 3], t[n - 2], t[n - 1]];
    if (open?.kind === '(' && count?.kind === 'number' && word?.kind === 'word' && FILLER.has(word.text) && close?.kind === ')') {
      (this.tokens as Token[]).splice(n - 4, 4);
      return count.value;
    }
    return null;
  }

  /** item (',' item)*  — stops at ')' or at the end of a '*' repeat. */
  private items(depth: number, insideStar: boolean): Node[] {
    const nodes: Node[] = [];
    for (;;) {
      const token = this.peek();
      if (!token || token.kind === ')') break;
      if (insideStar && (token.kind === ';' || token.kind === '*' || this.isWord('rep') || this.isWord('repeat'))) break;
      if (token.kind === ',') {
        this.position++;
        continue;
      }
      nodes.push(this.item(depth));
    }
    return nodes;
  }

  private item(depth: number): Node {
    const token = this.peek();
    if (!token) throw new PatternError('instruction ends unexpectedly');
    if (token.kind === '*' || token.kind === '(') {
      if (depth >= LIMITS.nesting) throw new PatternError(`column ${token.column}: repeats are nested too deeply`);
      return token.kind === '*' ? this.starRepeat(depth) : this.groupRepeat(depth);
    }
    if (token.kind === 'word') return this.stitch(token);
    throw this.unexpected();
  }

  /** "*A, B; rep from * to end"  or  "*A, B* 3 times". No clause means "to end". */
  private starRepeat(depth: number): Node {
    const open = this.next();
    const body = this.items(depth + 1, true);
    if (body.length === 0) throw new PatternError(`column ${open.column}: empty repeat`);
    if (this.peek()?.kind === ';') this.position++;
    if (this.isWord('rep') || this.isWord('repeat')) {
      this.position++;
      if (this.isWord('from')) this.position++;
    }
    if (this.peek()?.kind === '*') this.position++;
    return { kind: 'repeat', body, mode: this.repeatClause() ?? { type: 'toEnd', leave: 0 } };
  }

  /** "(K1, P1) 3 times". A group with no clause is done once. */
  private groupRepeat(depth: number): Node {
    const open = this.next();
    const body = this.items(depth + 1, false);
    if (this.peek()?.kind !== ')') throw new PatternError(`column ${open.column}: bracket is never closed`);
    this.position++;
    if (body.length === 0) throw new PatternError(`column ${open.column}: empty brackets`);
    return { kind: 'repeat', body, mode: this.repeatClause() ?? { type: 'times', times: 1 } };
  }

  /** "to end" | "across" | "to last N sts" | "N times" | "N more times" | "twice". */
  private repeatClause(): RepeatMode | null {
    if (this.isWord('across')) {
      this.position++;
      return { type: 'toEnd', leave: 0 };
    }
    if (this.isWord('to')) return { type: 'toEnd', leave: this.toClause() };
    const token = this.peek();
    const word = token?.kind === 'word' ? NUMBER_WORDS.get(token.text) : undefined;
    if (word !== undefined) {
      this.position++;
      return { type: 'times', times: word };
    }
    if (token?.kind === 'number') {
      this.position++;
      let times = token.value;
      if (this.isWord('more')) {
        this.position++;
        times += 1; // "repeat 3 more times" means 4 in total
      }
      if (!this.isWord('times') && !this.isWord('time')) throw new PatternError(`column ${token.column}: expected "times" after the number`);
      this.position++;
      return { type: 'times', times };
    }
    return null;
  }

  /** After "to": "end" (leave 0) or "last N st(s)" / "last st" (leave N). */
  private toClause(): number {
    const to = this.next();
    if (this.isWord('end')) {
      this.position++;
      return 0;
    }
    if (this.isWord('last')) {
      this.position++;
      let leave = 1;
      const count = this.peek();
      if (count?.kind === 'number') {
        leave = count.value;
        this.position++;
      }
      this.skipFiller();
      return leave;
    }
    throw new PatternError(`column ${to.column}: expected "to end" or "to last N sts"`);
  }

  private stitch(token: Extract<Token, { kind: 'word' }>): Node {
    this.position++;
    let name = ALIASES.get(token.text) ?? token.text;
    let times: number | null = null;
    let stitch = STITCHES.get(name);
    if (!stitch) {
      // "k12" -> stitch "k", 12 times. Split letters from trailing digits by hand.
      let split = name.length;
      while (split > 0 && name.charAt(split - 1) >= '0' && name.charAt(split - 1) <= '9') split--;
      const base = ALIASES.get(name.slice(0, split)) ?? name.slice(0, split);
      const candidate = STITCHES.get(base);
      if (candidate?.countable && split > 0 && split < name.length) {
        if (name.length - split > 6) throw new PatternError(`column ${token.column}: number is too large`);
        stitch = candidate;
        times = Number(name.slice(split));
        name = base;
      }
    }
    if (!stitch) throw new PatternError(`column ${token.column}: unknown stitch "${token.text}"`);

    if (stitch.countable && times === null) {
      const following = this.peek();
      if (following?.kind === 'number') {
        times = following.value;
        this.position++;
        this.skipFiller();
      } else if (this.isWord('to')) {
        return { kind: 'rest', name, stitch, leave: this.toClause() };
      } else if (this.isWord('across') || this.isWord('all')) {
        this.position++;
        this.skipFiller();
        return { kind: 'rest', name, stitch, leave: 0 };
      } else if (token.text.length > 1 && token.text !== 'sl' && token.text !== 'bo' && token.text !== 'co') {
        // A spelled-out "Knit" or "Purl" on its own means the whole row.
        return { kind: 'rest', name, stitch, leave: 0 };
      }
    }
    const node: Node = { kind: 'stitch', name, stitch, times: times ?? 1 };
    // "K2tog across" or "K2tog to end": one stitch repeated along the row.
    if (this.isWord('across') || this.isWord('to')) {
      const mode = this.repeatClause();
      if (mode) return { kind: 'repeat', body: [node], mode };
    }
    return node;
  }

  private skipFiller(): void {
    const token = this.peek();
    if (token?.kind === 'word' && FILLER.has(token.text)) this.position++;
  }

  private isWord(text: string): boolean {
    const token = this.peek();
    return token?.kind === 'word' && token.text === text;
  }

  private peek(): Token | undefined {
    return this.tokens[this.position];
  }

  private next(): Token {
    const token = this.tokens[this.position++];
    if (!token) throw new PatternError('instruction ends unexpectedly');
    return token;
  }

  private unexpected(): PatternError {
    const token = this.peek();
    if (!token) return new PatternError('instruction ends unexpectedly');
    const shown = token.kind === 'word' ? `"${token.text}"` : token.kind === 'number' ? `number ${token.value}` : `"${token.kind}"`;
    return new PatternError(`column ${token.column}: did not expect ${shown} here`);
  }
}

export function parseRow(tokens: Token[]): ParsedRow {
  return new Parser([...tokens]).parseRow();
}
