// Quiz logic: builds the five questions for a strip and marks answers.
// Pure functions only, so everything here is tested without a browser.

import { measure } from './measure.js';
import { RHYTHMS, generateStrip } from './rhythms.js';
import { mulberry32, shuffle } from './rng.js';

const NAME = Object.fromEntries(RHYTHMS.map((r) => [r.id, r.name]));

export const EXPLANATIONS = {
  nsr: 'Rate 60–100, regular, a P wave before every narrow QRS, normal PR interval.',
  brady: 'Everything looks normal except the rate, which is below 60.',
  tachy: 'Everything looks normal except the rate, which is above 100.',
  afib: 'Irregularly irregular with no P waves: the baseline just wobbles. Narrow QRS.',
  flutter: 'Sawtooth flutter waves between regular, narrow QRS complexes.',
  pvc: 'A sinus rhythm interrupted by early, wide beats with no P wave, each followed by a pause.',
  avb1: 'Like normal sinus rhythm, but the PR interval is longer than 200 ms (one large box).',
  vt: 'Fast, regular, wide QRS complexes with no visible P waves. A medical emergency in real life.',
};

/** Builds a question set. The seed decides both the rhythm and the tracing. */
export function buildQuestion(seed) {
  const rand = mulberry32(seed ^ 0x9e3779b9);
  const rhythm = RHYTHMS[Math.floor(rand() * RHYTHMS.length)];
  const strip = generateStrip(rhythm.id, seed);
  const m = measure(strip);

  const distractors = shuffle(rand, RHYTHMS.filter((r) => r.id !== rhythm.id)).slice(0, 3);
  const nameOptions = shuffle(rand, [rhythm, ...distractors]);

  const steps = [
    {
      id: 'rate',
      prompt: 'Rate: count the QRS complexes and multiply by 10.',
      options: [['slow', 'Slow (under 60)'], ['normal', 'Normal (60–100)'], ['fast', 'Fast (over 100)']],
      answer: m.rateClass,
      detail: `${m.beatCount} complexes in 6 seconds, about ${m.rate} beats per minute.`,
    },
    {
      id: 'regular',
      prompt: 'Rhythm: are the R peaks evenly spaced?',
      options: [['yes', 'Regular'], ['no', 'Irregular']],
      answer: m.regular ? 'yes' : 'no',
      detail: m.regular ? 'The gaps between R peaks are almost identical.' : `The gaps between R peaks vary by about ${Math.round(m.variation * 100)}%.`,
    },
    {
      id: 'p',
      prompt: 'P waves: is there one before each QRS?',
      options: [['every', 'Before every QRS'], ['most', 'Before most, but not all'], ['none', 'None visible'], ['sawtooth', 'Sawtooth waves instead']],
      answer: m.pWaves,
      detail: { every: `Each QRS has a P wave${m.prMs ? `, PR interval about ${m.prMs} ms` : ''}.`, most: 'The early, wide beats have no P wave.', none: 'No P waves can be found.', sawtooth: 'The baseline is a sawtooth of flutter waves.' }[m.pWaves],
    },
    {
      id: 'qrs',
      prompt: 'QRS: narrow or wide? (Wide is more than 3 small boxes.)',
      options: [['narrow', 'Narrow'], ['wide', 'Wide'], ['mixed', 'Mostly narrow, some wide']],
      answer: m.qrs,
      detail: { narrow: 'Every QRS is narrow.', wide: 'Every QRS is wide.', mixed: 'Most are narrow, but the early beats are wide.' }[m.qrs],
    },
    {
      id: 'name',
      prompt: 'Putting it together: what is this rhythm?',
      options: nameOptions.map((r) => [r.id, r.name]),
      answer: rhythm.id,
      detail: `${NAME[rhythm.id]}. ${EXPLANATIONS[rhythm.id]}`,
    },
  ];
  return { seed, strip, measured: m, steps };
}

/** Marks one answer. Unknown steps or choices are simply wrong, never an error. */
export function grade(question, stepIndex, choice) {
  if (!Number.isInteger(stepIndex)) return false;
  const step = question.steps[stepIndex];
  if (!step || !step.options.some(([value]) => value === choice)) return false;
  return step.answer === choice;
}
