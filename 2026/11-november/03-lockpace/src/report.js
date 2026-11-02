// The printed report: team sizes compared, a timeline, hint deadlines and warnings.

/** @typedef {import('./parse.js').Room} Room @typedef {ReturnType<typeof import('./analyse.js').analyse>} Analysis */

const LABELS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const WIDTH = 72;

/** Tenths of a minute as m:ss. @param {number} t */
export function clock(t) {
  const secs = Math.round(t * 6);
  return `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
}

/** @param {string} s @param {number} n */
const pad = (s, n) => s + ' '.repeat(Math.max(0, n - [...s].length));

/**
 * One row per player, one column per slice of time; '.' is a player with nothing to do.
 * @param {Room} room @param {import('./analyse.js').Run} run
 */
function timeline(room, run) {
  const end = /** @type {number} */ (run.finish);
  const step = Math.max(10, Math.ceil(end / WIDTH / 10) * 10); // whole minutes per column
  const cols = Math.ceil(end / step);
  const used = new Set(run.segments.map((s) => s.puzzle));
  const label = new Map([...used].sort((a, b) => a - b).map((p, i) => [p, LABELS[i]]));
  const rows = [];
  for (let player = 0; player < run.players; player++) {
    let row = '';
    for (let c = 0; c < cols; c++) {
      const mid = c * step + step / 2;
      const seg = run.segments.find((s) => s.players.includes(player) && s.start <= mid && mid < s.end);
      row += seg ? label.get(seg.puzzle) : '.';
    }
    rows.push(`  P${String(player + 1).padEnd(2)} |${row}|`);
  }
  const key = [...label].map(([p, l]) => `${l} ${room.puzzles[p].name}`);
  return { rows, key, step };
}

/** @param {Room} room @param {Analysis} a */
export function render(room, a) {
  const out = [];
  out.push(`LOCKPACE  ${room.title}`);
  out.push(`${room.puzzles.length} puzzles, a ${room.limit}-minute limit, teams of ${room.minPlayers === room.maxPlayers ? room.minPlayers : `${room.minPlayers} to ${room.maxPlayers}`}.`);
  out.push('');

  if (a.unlimited.finish === null) {
    out.push(`The room can't be finished: ${a.unlimited.stuck}.`);
  } else {
    out.push(`With as many players as it takes: ${clock(a.unlimited.finish)} (the longest chain of puzzles).`);
    out.push('');
    out.push('  Team  Finish   At best   Idle   Longest wait on one puzzle');
    for (const { run, bound } of a.runs) {
      if (run.finish === null) {
        out.push(`  ${String(run.players).padStart(4)}  stuck: ${run.stuck}`);
        continue;
      }
      const idle = `${Math.round((100 * run.idle) / (run.players * run.finish))}%`;
      const wait = run.wait.puzzle < 0 ? '-' : `${clock(run.wait.length)} (${room.puzzles[run.wait.puzzle].name})`;
      const late = run.finish > room.limit * 10 ? ' over time' : '';
      out.push(`  ${String(run.players).padStart(4)}  ${clock(run.finish).padStart(6)}${late}   ${clock(/** @type {number} */ (bound)).padStart(6)}   ${idle.padStart(4)}   ${wait}`);
    }
    out.push("  ('At best' is a floor no team can beat: the longest chain, or all the work shared out perfectly.)");
    const ok = a.runs.filter((r) => r.run.finish !== null);
    if (ok.length > 1) {
      const fastest = Math.min(...ok.map((r) => /** @type {number} */ (r.run.finish)));
      const enough = ok.find((r) => /** @type {number} */ (r.run.finish) <= fastest * 1.05);
      if (enough && enough.run.players < room.maxPlayers) {
        out.push('');
        out.push(`Beyond ${enough.run.players} players, extra people save less than 5% of the time and mostly stand about.`);
      }
    }
    const shown = a.runs.find((r) => r.run.players === (room.show ?? room.maxPlayers) && r.run.finish !== null) ?? ok[ok.length - 1];
    if (shown) {
      const t = timeline(room, shown.run);
      out.push('');
      out.push(`Timeline for ${shown.run.players} players (one column = ${t.step / 10} min, '.' = nothing to do):`);
      out.push(...t.rows);
      for (let i = 0; i < t.key.length; i += 3) out.push(`  ${t.key.slice(i, i + 3).map((k) => pad(k, 26)).join('').trimEnd()}`);
    }
    out.push('');
    out.push(`Hint deadlines: the latest each puzzle can start and still beat ${room.limit}:00, even with every player helping.`);
    out.push("If a team hasn't started a puzzle by then, they can't make it without a hint:");
    for (const d of a.deadlines) {
      const when = d.latest < 0 ? "can't make it" : clock(d.latest);
      out.push(`  ${pad(room.puzzles[d.puzzle].name, 28)} ${when.padStart(6)}`);
    }
  }
  if (a.warnings.length) {
    out.push('');
    out.push('Warnings:');
    for (const w of a.warnings) out.push(`  ! ${w}`);
  }
  return out.join('\n') + '\n';
}
