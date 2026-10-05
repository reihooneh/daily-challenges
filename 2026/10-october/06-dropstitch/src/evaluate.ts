// Step 3: "knit" the row with numbers instead of yarn.
//
// We track two counters: stitches still waiting on the left needle, and
// stitches made so far on the right needle. Repeats are worked out with
// division, never with a loop, so "repeat 99999 times" costs nothing.

import { LIMITS } from './errors.js';
import type { Node } from './parser.js';

export interface RowResult {
  readonly before: number;
  readonly after: number;
  readonly problems: readonly string[];
}

interface Needles {
  left: number;
  right: number;
}

/** What a list of instructions does when worked once. null = depends on what is left. */
function shape(nodes: readonly Node[]): { uses: number; makes: number } | null {
  let uses = 0;
  let makes = 0;
  for (const node of nodes) {
    if (node.kind === 'stitch') {
      uses += node.stitch.uses * node.times;
      makes += node.stitch.makes * node.times;
    } else if (node.kind === 'repeat' && node.mode.type === 'times') {
      const inner = shape(node.body);
      if (!inner) return null;
      uses += inner.uses * node.mode.times;
      makes += inner.makes * node.mode.times;
    } else {
      return null; // "to end" style instructions have no fixed size
    }
  }
  return { uses, makes };
}

function work(nodes: readonly Node[], needles: Needles, problems: string[]): void {
  for (const node of nodes) {
    if (problems.length > 0) return; // after the first problem the counts mean nothing
    if (node.kind === 'stitch') {
      const uses = node.stitch.uses * node.times;
      if (uses > needles.left) {
        const label = node.times > 1 ? `${node.name.toUpperCase()}${node.times}` : node.name.toUpperCase();
        problems.push(`${label} needs ${uses} stitch${uses === 1 ? '' : 'es'} but only ${needles.left} ${needles.left === 1 ? 'is' : 'are'} left`);
        return;
      }
      needles.left -= uses;
      needles.right += node.stitch.makes * node.times;
    } else if (node.kind === 'rest') {
      if (node.leave > needles.left) {
        problems.push(`"to last ${node.leave}" is impossible: only ${needles.left} stitch${needles.left === 1 ? ' is' : 'es are'} left`);
        return;
      }
      const count = needles.left - node.leave;
      needles.left -= count;
      needles.right += node.stitch.makes * count;
    } else if (node.mode.type === 'times') {
      const once = shape(node.body);
      if (once) {
        // Fixed-size body: multiply instead of looping.
        if (once.uses * node.mode.times > needles.left) {
          problems.push(`a repeat worked ${node.mode.times} time${node.mode.times === 1 ? '' : 's'} needs ${once.uses * node.mode.times} stitches but only ${needles.left} are left`);
          return;
        }
        needles.left -= once.uses * node.mode.times;
        needles.right += once.makes * node.mode.times;
      } else if (node.mode.times === 1) {
        work(node.body, needles, problems);
      } else {
        problems.push('a repeat containing "to end" cannot itself be repeated a set number of times');
      }
    } else {
      const once = shape(node.body);
      if (!once) {
        problems.push('a repeat "to end" cannot contain another "to end" instruction');
        return;
      }
      if (once.uses === 0) {
        problems.push('this repeat uses no stitches, so it would never reach the end of the row');
        return;
      }
      const span = needles.left - node.mode.leave;
      if (span < 0) {
        problems.push(`"to last ${node.mode.leave}" is impossible: only ${needles.left} stitches are left`);
        return;
      }
      const leftover = span % once.uses;
      if (leftover !== 0) {
        problems.push(`the repeat is ${once.uses} stitches wide but has ${span} to cover: ${leftover} left over`);
        return;
      }
      const times = span / once.uses;
      needles.left -= span;
      needles.right += once.makes * times;
    }
    if (needles.right > LIMITS.stitches) {
      problems.push(`more than ${LIMITS.stitches} stitches on the needle`);
      return;
    }
  }
}

export function evaluateRow(nodes: readonly Node[], before: number): RowResult {
  const needles: Needles = { left: before, right: 0 };
  const problems: string[] = [];
  work(nodes, needles, problems);
  if (problems.length === 0 && needles.left > 0) {
    problems.push(`${needles.left} stitch${needles.left === 1 ? ' is' : 'es are'} left unworked at the end of the row`);
  }
  return { before, after: problems.length === 0 ? needles.right : before, problems };
}
