// The page: draws the strip and runs the five-step quiz.
//
// Everything shown on screen is written with textContent or as SVG attributes
// built from numbers. No innerHTML anywhere, so no text can ever become markup.

import { detectBeats } from './measure.js';
import { buildQuestion, grade } from './quiz.js';
import { HEIGHT, PX_PER_SECOND, stripWidth, tracePath } from './render.js';
import { MAX_SEED, codeFor, parseCode } from './rng.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const $ = (id) => document.getElementById(id);

const el = {
  strip: $('strip'), code: $('code'), progress: $('progress'), title: $('step-title'),
  options: $('options'), feedback: $('feedback'), summary: $('summary'), next: $('next'),
  fresh: $('new'), input: $('code-input'), load: $('load'), loadError: $('load-error'), score: $('score'),
};

const state = { question: null, step: 0, results: [], strips: 0, perfect: 0, stepsRight: 0, stepsTotal: 0 };

function svg(tag, attrs) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, String(value));
  return node;
}

function drawStrip(strip, showMarks) {
  const width = stripWidth(strip.duration);
  el.strip.replaceChildren();
  el.strip.setAttribute('viewBox', `0 0 ${width} ${HEIGHT}`);

  // ECG paper: a line every 10 px (1 mm), heavier every 50 px (5 mm).
  for (let x = 0; x <= width; x += 10) {
    el.strip.append(svg('line', { x1: x, y1: 0, x2: x, y2: HEIGHT, class: x % 50 ? 'grid-minor' : 'grid-major' }));
  }
  for (let y = 0; y <= HEIGHT; y += 10) {
    el.strip.append(svg('line', { x1: 0, y1: y, x2: width, y2: y, class: y % 50 ? 'grid-minor' : 'grid-major' }));
  }
  el.strip.append(svg('path', { d: tracePath(strip.samples, strip.sampleRate), class: 'trace' }));

  if (showMarks) {
    // Caliper marks over each R peak, revealed once the rate has been answered.
    detectBeats(strip.samples, strip.sampleRate).forEach((t, i) => {
      const x = t * PX_PER_SECOND;
      el.strip.append(svg('line', { x1: x, y1: 22, x2: x, y2: 40, class: 'mark' }));
      const label = svg('text', { x, y: 16, class: 'mark-text' });
      label.textContent = String(i + 1);
      el.strip.append(label);
    });
  }
}

function showStep() {
  const step = state.question.steps[state.step];
  el.progress.textContent = `Step ${state.step + 1} of ${state.question.steps.length}`;
  el.title.textContent = step.prompt;
  el.feedback.textContent = '';
  el.feedback.className = 'feedback';
  el.next.hidden = true;
  el.summary.hidden = true;
  el.options.hidden = false;
  el.options.replaceChildren(
    ...step.options.map(([value, label]) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.addEventListener('click', () => answer(value));
      button.dataset.value = value;
      return button;
    }),
  );
}

function answer(choice) {
  const step = state.question.steps[state.step];
  const correct = grade(state.question, state.step, choice);
  state.results.push(correct);

  for (const button of el.options.children) {
    button.disabled = true;
    if (button.dataset.value === step.answer) button.classList.add('right');
    else if (button.dataset.value === choice) button.classList.add('wrong');
  }
  el.feedback.textContent = `${correct ? 'Correct.' : 'Not quite.'} ${step.detail}`;
  el.feedback.className = `feedback ${correct ? 'right' : 'wrong'}`;

  if (step.id === 'rate') drawStrip(state.question.strip, true);

  const last = state.step === state.question.steps.length - 1;
  el.next.textContent = last ? 'See how you did' : 'Next';
  el.next.hidden = false;
  el.next.focus();
}

function showSummary() {
  const { steps } = state.question;
  const right = state.results.filter(Boolean).length;
  const named = state.results[steps.length - 1];
  const methodRight = right - (named ? 1 : 0);

  state.strips += 1;
  state.stepsRight += right;
  state.stepsTotal += steps.length;
  if (right === steps.length) state.perfect += 1;

  el.progress.textContent = 'Result';
  el.title.textContent = `${right} of ${steps.length} steps correct`;
  el.options.hidden = true;
  el.next.hidden = true;

  let verdict = 'Work through the steps again on a new strip.';
  if (right === steps.length) verdict = 'Right answer, right method.';
  else if (named && methodRight < steps.length - 1) verdict = 'You named the rhythm, but a step along the way was off. A lucky guess will not hold up on a harder strip.';
  else if (!named && methodRight === steps.length - 1) verdict = 'Your observations were all correct. Only the final name was missing: read the explanation below.';
  el.feedback.textContent = verdict;
  el.feedback.className = 'feedback';

  const labels = { rate: 'Rate', regular: 'Regularity', p: 'P waves', qrs: 'QRS width', name: 'Rhythm' };
  el.summary.replaceChildren(
    ...steps.map((step, i) => {
      const item = document.createElement('li');
      item.className = state.results[i] ? 'right' : 'wrong';
      item.textContent = `${state.results[i] ? '✓' : '✗'} ${labels[step.id]}: ${step.detail}`;
      return item;
    }),
  );
  el.summary.hidden = false;
  el.score.textContent = `This session: ${state.strips} strip${state.strips === 1 ? '' : 's'}, ${state.perfect} perfect, ${state.stepsRight} of ${state.stepsTotal} steps correct.`;
  el.fresh.focus();
}

function start(seed) {
  state.question = buildQuestion(seed);
  state.step = 0;
  state.results = [];
  const code = codeFor(seed);
  el.code.textContent = code;
  el.loadError.textContent = '';
  // The code goes after "#", which browsers never send to a server.
  history.replaceState(null, '', `#${code}`);
  drawStrip(state.question.strip, false);
  showStep();
}

function randomSeed() {
  const box = new Uint32Array(1);
  crypto.getRandomValues(box);
  return box[0] % (MAX_SEED + 1);
}

el.next.addEventListener('click', () => {
  if (state.step === state.question.steps.length - 1) return showSummary();
  state.step += 1;
  showStep();
  el.options.firstElementChild?.focus();
});

el.fresh.addEventListener('click', () => start(randomSeed()));

function loadFromInput() {
  const seed = parseCode(el.input.value);
  if (seed === null) {
    el.loadError.textContent = 'That is not a strip code. Codes are 1 to 7 letters and digits, for example K7Q2M.';
    return;
  }
  el.input.value = '';
  start(seed);
}
el.load.addEventListener('click', loadFromInput);
el.input.addEventListener('keydown', (event) => { if (event.key === 'Enter') loadFromInput(); });

window.addEventListener('hashchange', () => {
  const seed = parseCode(location.hash.slice(1));
  if (seed !== null && codeFor(seed) !== el.code.textContent) start(seed);
});

// A link such as .../#K7Q2M opens that exact strip. Anything invalid is ignored.
start(parseCode(location.hash.slice(1)) ?? randomSeed());
