// The page. All text is written with textContent, and all layout numbers are
// set through the style object, so nothing from the user is ever parsed as HTML.

import {
  DAYS, buildInput, clock, decodeShare, describeMinutes, encodeShare,
  friendlyError, gridBounds, sampleState, sanitizeState, withoutWish,
} from './state.js';

const $ = (id) => document.getElementById(id);
const SOLVE_TIMEOUT_MS = 20000;

const ui = {
  courses: $('courses'), sample: $('sample'), noDays: $('no-days'), busy: $('busy'),
  verdict: $('verdict'), why: $('why'), conflict: $('conflict'), ways: $('ways'), wayList: $('way-list'),
  plan: $('plan'), planTitle: $('plan-title'), planStats: $('plan-stats'), grid: $('grid'),
  tableBody: document.querySelector('#plan-table tbody'), share: $('share'), shareNote: $('share-note'),
};
const toggles = {
  before: { on: $('before-on'), time: $('before-time') },
  after: { on: $('after-on'), time: $('after-time') },
  maxDays: { on: $('days-on'), n: $('days-n') },
  maxHours: { on: $('hours-on'), n: $('hours-n') },
  minGap: { on: $('gap-on'), n: $('gap-n') },
  lunch: { on: $('lunch-on'), n: $('lunch-n'), from: $('lunch-from'), to: $('lunch-to') },
};

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// ---- form <-> state -----------------------------------------------------------

DAYS.forEach((name, day) => {
  const label = el('label', 'chip');
  const box = el('input');
  box.type = 'checkbox';
  box.value = String(day);
  label.append(box, el('span', '', name));
  ui.noDays.append(label);
});

function readForm() {
  const raw = {
    courses: ui.courses.value,
    busy: ui.busy.value,
    noDays: [...ui.noDays.querySelectorAll('input:checked')].map((box) => Number(box.value)),
  };
  for (const [key, controls] of Object.entries(toggles)) {
    raw[key] = { on: controls.on.checked };
    for (const [field, input] of Object.entries(controls)) {
      if (field !== 'on') raw[key][field] = input.type === 'number' ? Number(input.value) : input.value;
    }
  }
  return sanitizeState(raw);
}

function writeForm(state) {
  ui.courses.value = state.courses;
  ui.busy.value = state.busy;
  for (const box of ui.noDays.querySelectorAll('input')) box.checked = state.noDays.includes(Number(box.value));
  for (const [key, controls] of Object.entries(toggles)) {
    for (const [field, input] of Object.entries(controls)) {
      if (field === 'on') input.checked = state[key].on;
      else input.value = String(state[key][field]);
    }
  }
}

// ---- talking to the planner ---------------------------------------------------

let worker = null;
let requestId = 0;
let timer = null;
let latest = null; // { response, sources, courseLines }

function startWorker() {
  worker = new Worker('worker.js');
  worker.onmessage = (event) => {
    if (event.data.id !== requestId) return; // an older request: ignore
    clearTimeout(timer);
    let response;
    try {
      response = JSON.parse(event.data.json);
    } catch {
      response = { status: 'error', error: 'The planner returned something unreadable.' };
    }
    latest.response = response;
    render();
  };
  worker.onerror = () => {
    clearTimeout(timer);
    showVerdict('error', 'The planner could not start in this browser.');
  };
}

function solve() {
  const { text, sources, courseLines } = buildInput(readForm());
  latest = { response: null, sources, courseLines };
  requestId += 1;
  clearTimeout(timer);
  timer = setTimeout(() => {
    // The planner has its own work limits; this is the backstop behind them.
    worker.terminate();
    startWorker();
    showVerdict('error', 'That took too long, so it was stopped. Try fewer options per class.');
  }, SOLVE_TIMEOUT_MS);
  worker.postMessage({ id: requestId, text });
}

let debounce = null;
function solveSoon() {
  clearTimeout(debounce);
  debounce = setTimeout(solve, 250);
}

// ---- rendering ----------------------------------------------------------------

function showVerdict(kind, text) {
  ui.verdict.className = `verdict ${kind}`;
  ui.verdict.textContent = text;
  if (kind === 'error') {
    ui.why.hidden = true;
    ui.ways.hidden = true;
    ui.plan.hidden = true;
  }
}

function render() {
  const { response, courseLines } = latest;
  ui.why.hidden = true;
  ui.ways.hidden = true;
  ui.plan.hidden = true;

  if (response.status === 'ok') {
    showVerdict('ok', 'Everything fits. Here is your best timetable.');
    showPlan(response, response.plan, 'Your timetable');
  } else if (response.status === 'impossible') {
    showVerdict('no', "You can't have all of that at once.");
    showConflict(response);
    showWaysOut(response);
  } else {
    showVerdict('error', friendlyError(response.error ?? 'Something went wrong.', courseLines));
  }
}

function showConflict(response) {
  ui.conflict.replaceChildren(...(response.conflict ?? []).map((row) => {
    const item = el('li', row.kind);
    item.append(el('span', 'tag', row.kind === 'course' ? 'Course' : 'Wish'), el('strong', '', row.text));
    if (row.detail) item.append(el('span', 'detail', row.detail));
    return item;
  }));
  ui.why.hidden = false;
}

function showWaysOut(response) {
  const ways = response.waysOut ?? [];
  ui.ways.hidden = false;
  $('ways-hint').textContent = ways.length === 0
    ? 'No small change fixes this. Try different class times or fewer courses.'
    : `The smallest things you could give up.${response.complete === false ? ' (The search was cut short, so there may be more.)' : ''} Pick one to see the timetable you'd get.`;

  const cards = ways.map((way, index) => {
    const card = el('article', 'way');
    const isCourse = way.drop[0].kind === 'course';
    card.append(el('p', 'way-label', isCourse ? 'Drop a course' : `Give up ${way.drop.length === 1 ? 'one wish' : `${way.drop.length} wishes`}`));
    const list = el('ul', 'way-drop');
    for (const row of way.drop) list.append(el('li', '', row.text));
    card.append(list, el('p', 'way-result', `${way.plan.days} day${way.plan.days === 1 ? '' : 's'} on campus, ${describeMinutes(way.plan.idleMinutes)}`));

    const buttons = el('div', 'way-buttons');
    const preview = el('button', 'ghost', 'Show this timetable');
    preview.type = 'button';
    preview.setAttribute('aria-pressed', 'false');
    preview.addEventListener('click', () => {
      for (const other of ui.wayList.querySelectorAll('.way')) {
        other.classList.remove('selected');
        other.querySelector('.ghost').setAttribute('aria-pressed', 'false');
      }
      card.classList.add('selected');
      preview.setAttribute('aria-pressed', 'true');
      showPlan(response, way.plan, `Timetable if you give up: ${way.drop.map((row) => row.text).join(' + ')}`);
    });
    buttons.append(preview);

    const sources = way.drop.map((row) => sourceFor(response, row));
    if (!isCourse && sources.every(Boolean)) {
      const apply = el('button', 'primary', 'Give this up');
      apply.type = 'button';
      apply.addEventListener('click', () => {
        // Remove busy lines from the bottom up so earlier indexes stay valid.
        const ordered = [...sources].sort((a, b) => (b.index ?? 0) - (a.index ?? 0));
        writeForm(ordered.reduce(withoutWish, readForm()));
        solve();
        ui.verdict.focus();
      });
      buttons.append(apply);
    }
    card.append(buttons);
    if (index === 0) queueMicrotask(() => preview.click());
    return card;
  });
  ui.wayList.replaceChildren(...cards);
}

/** Finds the form control behind a wish. Wishes typed into the class list have none. */
function sourceFor(response, row) {
  if (row.kind !== 'wish') return null;
  const typedInText = (response.wishes ?? []).length - latest.sources.length;
  return latest.sources[row.index - typedInText] ?? null;
}

function showPlan(response, plan, title) {
  ui.planTitle.textContent = title;
  ui.planStats.textContent = `${plan.days} day${plan.days === 1 ? '' : 's'} on campus · ${describeMinutes(plan.idleMinutes)}${plan.optimal ? '' : ' · search stopped early, so this may not be the very best'}`;
  const { firstHour, lastHour, days } = gridBounds(plan.classes);
  const span = (lastHour - firstHour) * 60;

  const grid = ui.grid;
  grid.replaceChildren();
  grid.style.setProperty('--days', String(days));
  grid.style.setProperty('--hours', String(lastHour - firstHour));

  const axis = el('div', 'axis');
  axis.append(el('div', 'day-name'));
  const axisBody = el('div', 'day-body');
  for (let hour = firstHour; hour < lastHour; hour++) {
    const tick = el('span', 'tick', clock(hour * 60));
    tick.style.top = `${((hour - firstHour) * 60 / span) * 100}%`;
    axisBody.append(tick);
  }
  axis.append(axisBody);
  grid.append(axis);

  for (let day = 0; day < days; day++) {
    const column = el('div', 'day');
    const classes = plan.classes.filter((c) => c.day === day);
    column.append(el('div', `day-name${classes.length ? '' : ' free'}`, DAYS[day]));
    const body = el('div', 'day-body');
    for (const c of classes) {
      const course = response.courses[c.course];
      const block = el('div', `block c${c.course % 8}${c.end - c.start <= 60 ? ' short' : ''}`);
      block.style.top = `${((c.start - firstHour * 60) / span) * 100}%`;
      block.style.height = `${((c.end - c.start) / span) * 100}%`;
      block.title = `${course.code} ${c.component}, ${DAYS[c.day]} ${clock(c.start)}-${clock(c.end)}`;
      block.append(el('strong', '', course.code), el('span', '', c.component), el('span', 'when', `${clock(c.start)}-${clock(c.end)}`));
      body.append(block);
    }
    if (classes.length === 0) body.append(el('span', 'free-label', 'free'));
    column.append(body);
    grid.append(column);
  }

  ui.tableBody.replaceChildren(...plan.classes.map((c) => {
    const row = el('tr');
    row.append(el('td', '', DAYS[c.day]), el('td', '', `${clock(c.start)}-${clock(c.end)}`),
      el('td', '', response.courses[c.course].code), el('td', '', c.component));
    return row;
  }));
  ui.plan.hidden = false;
}

// ---- events -------------------------------------------------------------------

for (const node of document.querySelectorAll('.inputs input, .inputs textarea')) {
  node.addEventListener('input', solveSoon);
  node.addEventListener('change', solveSoon);
}

ui.sample.addEventListener('change', () => {
  writeForm(sampleState(ui.sample.value));
  solve();
});

ui.share.addEventListener('click', async () => {
  const encoded = encodeShare(readForm());
  const link = `${location.origin}${location.pathname}#${encoded}`;
  if (link.length > 8000) {
    ui.shareNote.textContent = 'This plan is too large to fit in a link.';
    return;
  }
  history.replaceState(null, '', `#${encoded}`);
  try {
    await navigator.clipboard.writeText(link);
    ui.shareNote.textContent = 'Link copied. Anyone who opens it sees this plan.';
  } catch {
    ui.shareNote.textContent = 'The link is now in your address bar: copy it from there.';
  }
});

ui.verdict.tabIndex = -1;
startWorker();
writeForm(decodeShare(location.hash.slice(1)) ?? sampleState('friday'));
if (location.hash.length > 1 && decodeShare(location.hash.slice(1)) === null) {
  history.replaceState(null, '', location.pathname); // a broken or hostile link: drop it
}
solve();
