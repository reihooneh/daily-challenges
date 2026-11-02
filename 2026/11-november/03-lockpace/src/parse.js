// The room file: puzzles, the items each needs, uses up and gives, and the room's settings.
// Every line must match a fixed shape and every number has a range. Errors give the line number
// and what was expected, never the text of the line.

export const LIMITS = Object.freeze({ bytes: 32 * 1024, line: 200, puzzles: 60, items: 120, players: 12 });

export class RoomError extends Error {}

const NAME = /^[\p{L}\p{N}][\p{L}\p{N} '.,&-]{0,39}$/u;
const ITEM = /^[\p{Ll}\p{Lo}\p{N}][\p{Ll}\p{Lo}\p{N} '-]{0,29}$/u;
const HIDDEN = /[\p{Cc}\p{Cf}]/u;
const PUZZLE = /^puzzle\s+(.+?)\s*\(\s*(\d{1,3}(?:\.\d)?)\s*min(?:\s*,\s*(\d{1,2})\s*(?:people|person))?\s*\)\s*(.*)$/;

/**
 * @typedef {{ name: string, time: number, crew: number, needs: string[], uses: string[], gives: string[], line: number }} Puzzle
 * @typedef {{ title: string, limit: number, minPlayers: number, maxPlayers: number, show: number | null,
 *             goal: string, start: string[], puzzles: Puzzle[] }} Room
 */

/** @param {number} line @param {string} msg */
function fail(line, msg) {
  return new RoomError(line ? `line ${line}: ${msg}` : msg);
}

/** @param {string} raw @param {number} line */
function name(raw, line) {
  const n = raw.trim().replace(/\s+/g, ' ');
  if (!NAME.test(n)) throw fail(line, "names use letters, digits, spaces and ' . , & - (up to 40), starting with a letter or digit");
  return n;
}

/** Item lists: "brass key, oil can". Items are matched in lower case. @param {string} raw @param {number} line */
function items(raw, line) {
  /** @type {string[]} */
  const out = [];
  for (const part of raw.split(',')) {
    const it = part.trim().replace(/\s+/g, ' ').toLowerCase();
    if (!ITEM.test(it)) throw fail(line, "items use letters, digits, spaces, ' and - (up to 30), separated by commas");
    if (out.includes(it)) throw fail(line, 'an item is listed twice');
    out.push(it);
  }
  return out;
}

/** "needs a, b uses c gives d" in any order, each at most once. @param {string} rest @param {number} line */
function clauses(rest, line) {
  /** @type {Record<string, string[]>} */
  const found = { needs: [], uses: [], gives: [] };
  if (!rest) return found;
  const parts = rest.split(/\b(needs|uses|gives)\b/).map((s) => s.trim());
  if (parts[0] !== '') throw fail(line, "after the brackets come 'needs', 'uses' and 'gives' lists");
  const seen = new Set();
  for (let i = 1; i < parts.length; i += 2) {
    const key = parts[i];
    if (seen.has(key)) throw fail(line, `'${key}' comes once per puzzle`);
    seen.add(key);
    if (!parts[i + 1]) throw fail(line, `'${key}' needs at least one item`);
    found[key] = items(parts[i + 1], line);
  }
  return found;
}

/** @param {string} text @returns {Room} */
export function parseRoom(text) {
  if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) throw fail(0, 'the room file is larger than 32 KB');
  /** @type {Room} */
  const room = { title: 'Escape room', limit: 60, minPlayers: 2, maxPlayers: 6, show: null, goal: '', start: [], puzzles: [] };
  const seen = new Set();
  const names = new Set();
  const lines = text.replace(/^\uFEFF/, '').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const n = i + 1;
    const raw = lines[i].replace(/\r$/, '');
    if ([...raw].length > LIMITS.line) throw fail(n, `is longer than ${LIMITS.line} characters`);
    if (/[\p{Cc}]/u.test(raw.replace(/\t/g, ' '))) throw fail(n, 'contains a control character');
    if (HIDDEN.test(raw)) throw fail(n, 'contains an invisible formatting character');
    const line = raw.split('#')[0].trim().replace(/\s+/g, ' ');
    if (!line) continue;
    const [head] = line.split(' ');
    const rest = line.slice(head.length).trim();
    const once = () => {
      if (seen.has(head)) throw fail(n, `'${head}' comes once`);
      seen.add(head);
    };
    let m;
    switch (head) {
      case 'room':
        once();
        room.title = name(rest, n);
        break;
      case 'limit':
        once();
        if (!(m = /^(\d{1,3}) ?(?:min)?$/.exec(rest)) || +m[1] < 5 || +m[1] > 240) throw fail(n, "write the time limit like 'limit 60' (5 to 240 minutes)");
        room.limit = +m[1];
        break;
      case 'players':
        once();
        if (!(m = /^(\d{1,2})(?:-(\d{1,2}))?$/.exec(rest))) throw fail(n, "write the team size like 'players 2-6' or 'players 4'");
        room.minPlayers = +m[1];
        room.maxPlayers = m[2] === undefined ? +m[1] : +m[2];
        if (room.minPlayers < 1 || room.maxPlayers > LIMITS.players || room.minPlayers > room.maxPlayers) throw fail(n, `team sizes run from 1 to ${LIMITS.players}, smaller first`);
        break;
      case 'show':
        once();
        if (!(m = /^(\d{1,2})$/.exec(rest)) || +m[1] < 1 || +m[1] > LIMITS.players) throw fail(n, `write 'show 4' to draw the timeline for 4 players (1 to ${LIMITS.players})`);
        room.show = +m[1];
        break;
      case 'goal':
        once();
        [room.goal] = items(rest, n);
        if (rest.includes(',')) throw fail(n, 'the goal is one item');
        break;
      case 'start':
        once();
        room.start = items(rest, n);
        break;
      case 'puzzle': {
        if (!(m = PUZZLE.exec(line))) throw fail(n, "write a puzzle like 'puzzle Clock face (8 min, 2 people) needs brass key gives gear'");
        const pname = name(m[1], n);
        if (names.has(pname.toLowerCase())) throw fail(n, 'two puzzles have the same name');
        names.add(pname.toLowerCase());
        const time = Math.round(+m[2] * 10);
        const crew = m[3] === undefined ? 1 : +m[3];
        if (time < 1 || time > 1200) throw fail(n, 'a puzzle takes 0.1 to 120 minutes');
        if (crew < 1 || crew > LIMITS.players) throw fail(n, `a puzzle needs 1 to ${LIMITS.players} people`);
        if (room.puzzles.length >= LIMITS.puzzles) throw fail(n, `at most ${LIMITS.puzzles} puzzles`);
        const c = clauses(m[4], n);
        const both = c.needs.filter((x) => c.uses.includes(x));
        if (both.length) throw fail(n, 'an item is both needed and used up by the same puzzle');
        room.puzzles.push({ name: pname, time, crew, needs: c.needs, uses: c.uses, gives: c.gives, line: n });
        break;
      }
      default:
        throw fail(n, 'lines start with room, limit, players, show, goal, start or puzzle');
    }
  }
  if (!room.puzzles.length) throw fail(0, 'the room has no puzzles');
  if (!room.goal) throw fail(0, "the room needs a 'goal' line: the item that opens the exit");
  const all = new Set(room.start);
  for (const p of room.puzzles) for (const it of [...p.needs, ...p.uses, ...p.gives]) all.add(it);
  if (all.size > LIMITS.items) throw fail(0, `at most ${LIMITS.items} different items`);
  return room;
}
