// Reads a play's scene breakdown. One instruction per line:
//
//   title    The Lighthouse Keeper's Daughter
//   change   1:30                 default time to get into a costume
//   role     storm change 0:30    this costume is quicker (or slower)
//   between  0:20                 scene-change time between scenes
//   scene    1.1 8:00 : keeper mara>2:00 tobias<1:30
//   interval 15:00                a break between scenes
//
// In a scene, "mara>2:00" enters 2:00 after the scene starts and
// "tobias<1:30" leaves 1:30 before it ends; both can be combined.
//   together keeper ghost         a planned double: same actor
//   apart    mara nell            must be different actors
//
// Everything is allow-listed and size-limited, and error messages name the
// line and the problem without repeating the text.

export const LIMITS = Object.freeze({
  bytes: 64 * 1024,
  line: 200,
  scenes: 80,
  roles: 60,
  sceneSeconds: 3 * 60 * 60,
  changeSeconds: 30 * 60,
});

const ROLE = /^[a-z][a-z0-9_]{0,23}$/;
const LABEL = /^[0-9A-Za-z.]{1,8}$/;
const TITLE = /^[A-Za-z0-9 .,'!?&:-]{1,60}$/;
const TIME = /^(\d{1,3})(?::(\d{2}))?$/;
const CUE = /^([a-z][a-z0-9_]{0,23})(?:>(\d{1,3}(?::\d{2})?))?(?:<(\d{1,3}(?::\d{2})?))?$/;

export class PlayError extends Error {
  /** @param {string} message @param {number} [line] */
  constructor(message, line) {
    super(line ? `line ${line}: ${message}` : message);
    this.name = 'PlayError';
  }
}

/**
 * @typedef {{ role: string, enter: number, exit: number }} Cue  enter/exit: seconds after the start / before the end
 * @typedef {{ label: string, seconds: number, roles: string[], cues: Cue[], line: number }} Scene
 * @typedef {{ kind: 'scene', scene: Scene } | { kind: 'interval', seconds: number }} Step
 * @typedef {{
 *   title: string, defaultChange: number, between: number, changes: Map<string, number>,
 *   steps: Step[], scenes: Scene[], roles: string[],
 *   together: [string, string][], apart: [string, string][]
 * }} Play
 */

/** "8" means 8 minutes; "1:30" means 1 minute 30 seconds. @param {string} text @returns {number | null} */
export function parseTime(text) {
  const match = TIME.exec(text);
  if (!match) return null;
  const seconds = match[2] === undefined ? 0 : Number(match[2]);
  if (seconds > 59) return null;
  return Number(match[1]) * 60 + seconds;
}

/** @param {number} total */
export function formatTime(total) {
  const sign = total < 0 ? '-' : '';
  const t = Math.abs(Math.round(total));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = String(t % 60).padStart(2, '0');
  return h > 0 ? `${sign}${h}:${String(m).padStart(2, '0')}:${s}` : `${sign}${m}:${s}`;
}

/**
 * @param {unknown} text
 * @returns {Play}
 */
export function parsePlay(text) {
  if (typeof text !== 'string') throw new PlayError('the breakdown must be text');
  if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) throw new PlayError(`the breakdown is larger than ${LIMITS.bytes} bytes`);

  /** @type {Play} */
  const play = {
    title: 'Untitled play',
    defaultChange: 90,
    between: 0,
    changes: new Map(),
    steps: [],
    scenes: [],
    roles: [],
    together: [],
    apart: [],
  };
  /** @type {Map<string, number>} line where each role-specific change was set */
  const changeLines = new Map();
  const seenRoles = new Set();
  const labels = new Set();
  let seenChange = false;
  let seenBetween = false;

  const lines = text.split('\n');
  for (let index = 0; index < lines.length; index++) {
    const n = index + 1;
    let raw = lines[index];
    if (raw.endsWith('\r')) raw = raw.slice(0, -1);
    if (raw.length > LIMITS.line) throw new PlayError(`the line is longer than ${LIMITS.line} characters`, n);
    if (/[^\t\x20-\x7e]/.test(raw)) throw new PlayError('only plain printable ASCII text is allowed', n);
    const content = raw.replace(/#.*$/, '').trim();
    if (content === '') continue;
    const words = content.split(/[ \t]+/);
    const keyword = words[0];

    if (keyword === 'title') {
      const title = content.slice(5).trim();
      if (!TITLE.test(title)) throw new PlayError("the title must be 1-60 letters, digits, spaces or . , ' ! ? & : -", n);
      play.title = title;
    } else if (keyword === 'change') {
      if (seenChange) throw new PlayError('there can only be one default change line', n);
      const t = words.length === 2 ? parseTime(words[1]) : null;
      if (t === null || t > LIMITS.changeSeconds) throw new PlayError('write the default change time as M or M:SS, up to 30:00', n);
      play.defaultChange = t;
      seenChange = true;
    } else if (keyword === 'role') {
      if (words.length !== 4 || words[2] !== 'change') throw new PlayError('write it as: role NAME change M:SS', n);
      if (!ROLE.test(words[1])) throw new PlayError('the role name is not valid (a-z, 0-9 and _, starting with a letter)', n);
      const t = parseTime(words[3]);
      if (t === null || t > LIMITS.changeSeconds) throw new PlayError('the change time must be M or M:SS, up to 30:00', n);
      if (play.changes.has(words[1])) throw new PlayError(`this role's change time was already set on line ${changeLines.get(words[1])}`, n);
      play.changes.set(words[1], t);
      changeLines.set(words[1], n);
    } else if (keyword === 'scene') {
      if (words.length < 5 || words[3] !== ':') throw new PlayError('write a scene as: scene LABEL M:SS : ROLE ROLE ...', n);
      if (play.scenes.length >= LIMITS.scenes) throw new PlayError(`too many scenes (the limit is ${LIMITS.scenes})`, n);
      if (!LABEL.test(words[1])) throw new PlayError('the scene label may only use letters, digits and dots (up to 8)', n);
      if (labels.has(words[1])) throw new PlayError('this scene label is already used', n);
      const seconds = parseTime(words[2]);
      if (seconds === null || seconds < 1 || seconds > LIMITS.sceneSeconds)
        throw new PlayError('the scene length must be M or M:SS, from 0:01 to 180:00', n);
      /** @type {Cue[]} */
      const cues = [];
      const inScene = new Set();
      words.slice(4).forEach((word, i) => {
        const cue = CUE.exec(word);
        if (!cue) throw new PlayError(`role ${i + 1} is not valid (a name of a-z, 0-9 and _, optionally with >M:SS and <M:SS)`, n);
        const role = cue[1];
        const enter = cue[2] === undefined ? 0 : parseTime(cue[2]);
        const exit = cue[3] === undefined ? 0 : parseTime(cue[3]);
        if (enter === null || exit === null) throw new PlayError(`role ${i + 1} has an entrance or exit time that is not M:SS`, n);
        if (enter + exit >= seconds) throw new PlayError(`role ${i + 1} would leave before it arrives`, n);
        if (inScene.has(role)) throw new PlayError(`role ${i + 1} is listed twice in this scene`, n);
        inScene.add(role);
        cues.push({ role, enter, exit });
        if (!seenRoles.has(role)) {
          if (seenRoles.size >= LIMITS.roles) throw new PlayError(`too many roles (the limit is ${LIMITS.roles})`, n);
          seenRoles.add(role);
          play.roles.push(role);
        }
      });
      const roles = cues.map((c) => c.role);
      labels.add(words[1]);
      const scene = { label: words[1], seconds, roles, cues, line: n };
      play.scenes.push(scene);
      play.steps.push({ kind: 'scene', scene });
    } else if (keyword === 'between') {
      if (seenBetween) throw new PlayError('there can only be one between line', n);
      const t = words.length === 2 ? parseTime(words[1]) : null;
      if (t === null || t > LIMITS.changeSeconds) throw new PlayError('write the scene-change time as M:SS, up to 30:00', n);
      play.between = t;
      seenBetween = true;
    } else if (keyword === 'interval') {
      const t = words.length === 2 ? parseTime(words[1]) : null;
      if (t === null || t < 1 || t > LIMITS.sceneSeconds) throw new PlayError('write an interval as: interval M:SS', n);
      play.steps.push({ kind: 'interval', seconds: t });
    } else if (keyword === 'together' || keyword === 'apart') {
      if (words.length !== 3) throw new PlayError(`write it as: ${keyword} ROLE ROLE`, n);
      if (!ROLE.test(words[1]) || !ROLE.test(words[2])) throw new PlayError('a role name is not valid', n);
      if (words[1] === words[2]) throw new PlayError('the two roles must be different', n);
      (keyword === 'together' ? play.together : play.apart).push([words[1], words[2]]);
    } else {
      throw new PlayError('unknown keyword (expected title, change, role, between, scene, interval, together or apart)', n);
    }
  }

  if (play.scenes.length === 0) throw new PlayError('the breakdown has no scenes');
  for (const [role, line] of changeLines)
    if (!seenRoles.has(role)) throw new PlayError('this role never appears in any scene', line);
  for (const pair of [...play.together, ...play.apart])
    for (const role of pair) if (!seenRoles.has(role)) throw new PlayError('a together/apart line names a role that never appears in any scene');
  return play;
}
