import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  LIMITS, buildInput, decodeShare, defaultState, describeMinutes, encodeShare, friendlyError,
  gridBounds, sampleState, sanitizeState, withoutWish,
} from '../state.js';

test('the form becomes planner text, one wish per line', () => {
  const state = sampleState('friday');
  state.busy = 'Tue 14:00-18:00 work\n\n  Thu 9-10 gym  ';
  state.lunch.on = true;
  const { text, sources, courseLines } = buildInput(state);
  const wishes = text.split('\n').filter((line) => line.startsWith('wish:'));
  assert.deepEqual(wishes, [
    'wish: no classes on Fri',
    'wish: nothing before 10:00',
    'wish: at most 3 days',
    'wish: lunch 12:00-14:00 for 45 min',
    'wish: busy Tue 14:00-18:00 work',
    'wish: busy Thu 9-10 gym',
  ]);
  assert.deepEqual(sources.map((s) => s.type), ['noDay', 'before', 'maxDays', 'lunch', 'busy', 'busy']);
  assert.equal(courseLines, state.courses.split('\n').length);
});

test('giving up a wish switches off exactly that control', () => {
  const state = sampleState('friday');
  state.busy = 'Mon 9-10 a\nTue 9-10 b\nWed 9-10 c';
  assert.deepEqual(withoutWish(state, { type: 'noDay', day: 4 }).noDays, []);
  assert.equal(withoutWish(state, { type: 'before' }).before.on, false);
  assert.equal(withoutWish(state, { type: 'maxDays' }).maxDays.on, false);
  assert.equal(withoutWish(state, { type: 'busy', index: 1 }).busy, 'Mon 9-10 a\nWed 9-10 c');
  assert.equal(state.before.on, true, 'the original state is not modified');
  assert.deepEqual(withoutWish(state, { type: '__proto__' }), state);
  assert.deepEqual(withoutWish(state, { type: 'constructor' }), state);
});

test('a comment character in a busy line cannot swallow the line', () => {
  const state = defaultState();
  state.busy = 'Tue 9-10 # hidden';
  assert.match(buildInput(state).text, /wish: busy Tue 9-10 {3}hidden/);
});

test('share links round-trip, including non-English text', () => {
  const state = sampleState('firstyear');
  state.courses += '\nKORE1000 한국어 입문 Études\n  Lecture: Sat 10-12';
  state.busy = "Tue 14:00-18:00 Zoë's café";
  state.noDays = [0, 4];
  const encoded = encodeShare(state);
  assert.match(encoded, /^[A-Za-z0-9_-]+$/);
  assert.deepEqual(decodeShare(encoded), state);
});

test('hostile or broken share links are rejected, never half-applied', () => {
  const bad = ['', '!!!', '<script>alert(1)</script>', 'javascript:alert(1)', '%3Cimg%20src%3Dx%3E', 'AAAA', 'bnVsbA', 'WzEsMl0', 'InRleHQi',
    'x'.repeat(LIMITS.hashChars + 1), '../../etc/passwd', 'eyJjb3Vyc2VzIjo', 'gA'];
  for (const hash of bad) assert.equal(decodeShare(hash), null, hash.slice(0, 30));
  for (const value of [null, undefined, 42, {}, []]) assert.equal(decodeShare(value), null);
});

test('untrusted state is rebuilt field by field', () => {
  const hostile = JSON.parse(`{
    "courses": 42, "busy": {"x": 1}, "noDays": [4, 4, 9, -1, "2", 1.5, 0],
    "before": {"on": "yes", "time": "25:00"}, "after": {"on": true, "time": "<img src=x>"},
    "maxDays": {"on": true, "n": 99}, "maxHours": {"on": true, "n": "6"}, "minGap": null,
    "lunch": {"on": true, "n": 1e9, "from": "12:00", "to": "noon"},
    "__proto__": {"polluted": true}, "constructor": {"prototype": {"polluted": true}}, "extra": "ignored"
  }`);
  const clean = sanitizeState(hostile);
  const expected = defaultState();
  expected.noDays = [0, 4];
  expected.after.on = true;
  expected.maxDays.on = true;
  expected.maxHours.on = true;
  expected.lunch.on = true;
  assert.deepEqual(clean, expected);
  assert.deepEqual(Object.keys(clean), Object.keys(expected));
  assert.equal({}.polluted, undefined);
  assert.equal(sanitizeState({ courses: 'x'.repeat(LIMITS.coursesChars + 500) }).courses.length, LIMITS.coursesChars);
  for (const value of [null, 'text', 7, [], undefined]) assert.deepEqual(sanitizeState(value), defaultState());
});

test('planner errors are pointed at the right box', () => {
  assert.equal(friendlyError('line 3: expected a day', 10), 'Line 3 of your classes: expected a day');
  assert.equal(friendlyError('line 12: wish not understood', 10), 'In your wishes or busy times: wish not understood');
  assert.equal(friendlyError('no courses found', 0), 'no courses found');
});

test('grid bounds always cover a normal week and stretch for early, late and weekend classes', () => {
  assert.deepEqual(gridBounds([]), { firstHour: 9, lastHour: 17, days: 5 });
  assert.deepEqual(gridBounds([{ day: 5, start: 7 * 60 + 30, end: 20 * 60 + 15 }]), { firstHour: 7, lastHour: 21, days: 6 });
});

test('waiting time reads naturally', () => {
  assert.equal(describeMinutes(0), 'no waiting between classes');
  assert.equal(describeMinutes(60), '1 hour waiting between classes');
  assert.equal(describeMinutes(150), '2 hours 30 min waiting between classes');
  assert.equal(describeMinutes(45), '45 min waiting between classes');
});
