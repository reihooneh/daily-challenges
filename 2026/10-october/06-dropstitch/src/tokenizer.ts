// Step 1: turn a row's text into tokens.
//
// "K2, *YO, K2tog; rep from * to last 2 sts, K2."
//   -> word(k2) , * word(yo) , word(k2tog) ; word(rep) word(from) * word(to) ...
//
// Only letters, digits and a handful of punctuation marks are allowed through.
// Everything a later stage might print has therefore already been vetted.

import { LIMITS, PatternError } from './errors.js';

export type Token =
  | { readonly kind: 'word'; readonly text: string; readonly column: number }
  | { readonly kind: 'number'; readonly value: number; readonly column: number }
  | { readonly kind: ',' | ';' | '*' | '(' | ')'; readonly column: number };

const isLetter = (c: string): boolean => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
const isDigit = (c: string): boolean => c >= '0' && c <= '9';

export function tokenize(text: string): Token[] {
  if (text.length > LIMITS.lineLength) {
    throw new PatternError(`line is longer than ${LIMITS.lineLength} characters`);
  }
  const tokens: Token[] = [];
  let i = 0;
  while (i < text.length) {
    const c = text.charAt(i);
    const column = i + 1;
    if (c === ' ' || c === '\t' || c === '.' || c === ':') {
      i++;
    } else if (c === ',' || c === ';' || c === '*') {
      tokens.push({ kind: c, column });
      i++;
    } else if (c === '(' || c === '[') {
      tokens.push({ kind: '(', column });
      i++;
    } else if (c === ')' || c === ']') {
      tokens.push({ kind: ')', column });
      i++;
    } else if (isDigit(c)) {
      let end = i;
      while (end < text.length && isDigit(text.charAt(end))) end++;
      if (end - i > 6) throw new PatternError(`column ${column}: number is too large`);
      tokens.push({ kind: 'number', value: Number(text.slice(i, end)), column });
      i = end;
    } else if (isLetter(c)) {
      let end = i;
      while (end < text.length && (isLetter(text.charAt(end)) || isDigit(text.charAt(end)))) end++;
      if (end - i > LIMITS.wordLength) throw new PatternError(`column ${column}: word is too long`);
      tokens.push({ kind: 'word', text: text.slice(i, end).toLowerCase(), column });
      i = end;
    } else {
      // Deliberately does not show the character: it could be anything.
      throw new PatternError(`column ${column}: unexpected character`);
    }
  }
  return tokens;
}
