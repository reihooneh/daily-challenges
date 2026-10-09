// When is everyone on stage, and can one actor play two roles?

/**
 * @typedef {import('./parse.js').Play} Play
 * @typedef {{ label: string, start: number, end: number, roles: string[] }} TimedScene
 * @typedef {{ scene: number, start: number, end: number }} Appearance  on stage from start to end (seconds)
 * @typedef {{ from: string, to: string, fromScene: string, toScene: string, gap: number, needed: number, spare: number }} Change
 * @typedef {{ possible: false, sharedScene: string } | { possible: true, spare: number, tightest: Change | null }} Pair
 */

/**
 * Lay the scenes out on a clock (scene changes and intervals included) and
 * record exactly when each role is on stage.
 * @param {Play} play
 */
export function timeline(play) {
  /** @type {TimedScene[]} */
  const scenes = [];
  /** @type {Map<string, Appearance[]>} */
  const appearances = new Map(play.roles.map((r) => [r, []]));
  let clock = 0;
  let intervals = 0;
  let previousWasScene = false;
  for (const step of play.steps) {
    if (step.kind === 'interval') {
      clock += step.seconds;
      intervals++;
      previousWasScene = false;
      continue;
    }
    if (previousWasScene) clock += play.between;
    const { scene } = step;
    const index = scenes.length;
    scenes.push({ label: scene.label, start: clock, end: clock + scene.seconds, roles: scene.roles });
    for (const cue of scene.cues)
      appearances.get(cue.role)?.push({ scene: index, start: clock + cue.enter, end: clock + scene.seconds - cue.exit });
    clock += scene.seconds;
    previousWasScene = true;
  }
  return { scenes, appearances, runningTime: clock, intervals };
}

/** @param {Play} play @param {string} role */
export function changeTime(play, role) {
  return play.changes.get(role) ?? play.defaultChange;
}

/**
 * Could one actor play both roles? Walk through their appearances in time
 * order. They must never overlap, and every time the actor switches from
 * one role to the other, the time offstage must cover the change into the
 * new costume.
 *
 * @param {Play} play
 * @param {ReturnType<typeof timeline>} tl
 * @param {string} a
 * @param {string} b
 * @returns {Pair}
 */
export function pairing(play, tl, a, b) {
  const merged = [
    ...(tl.appearances.get(a) ?? []).map((ap) => ({ ...ap, role: a })),
    ...(tl.appearances.get(b) ?? []).map((ap) => ({ ...ap, role: b })),
  ].sort((x, y) => x.start - y.start || x.end - y.end);

  /** @type {Change | null} */
  let tightest = null;
  for (let k = 1; k < merged.length; k++) {
    const before = merged[k - 1];
    const after = merged[k];
    if (before.role === after.role) continue;
    if (after.start < before.end) return { possible: false, sharedScene: tl.scenes[after.scene].label };
    const gap = after.start - before.end;
    const needed = changeTime(play, after.role);
    const spare = gap - needed;
    if (tightest === null || spare < tightest.spare)
      tightest = {
        from: before.role,
        to: after.role,
        fromScene: tl.scenes[before.scene].label,
        toScene: tl.scenes[after.scene].label,
        gap,
        needed,
        spare,
      };
  }
  return { possible: true, spare: tightest ? tightest.spare : Infinity, tightest };
}
