import test from 'node:test';
import assert from 'node:assert/strict';
import { teachingEvents } from '../adapters/messier.mjs';
import { normalizeEvents } from '../core.mjs';

test('Messier uses dated session details with Jakarta dates rather than repeating weekly rows', () => {
  const events = teachingEvents([{
    course: { Id: 'course-1', Subject: 'Algorithms', Class: 'LZ01 ', Campus: 'ASM' },
    details: [
      { Id: 'session-1', Date: '2026-11-18T17:00:00.000Z', Shift: '15:20-17:00', Room: 'A1301' },
      { Id: 'session-2', Date: '2026-12-02T17:00:00.000Z', Shift: '15:20-17:00', Room: 'A1301' },
    ],
  }]);
  assert.equal(events.length, 2);
  assert.equal(events[0].start, '2026-11-19T15:20:00+07:00');
  assert.equal(events[1].start, '2026-12-03T15:20:00+07:00');
  assert.equal(events[0].id, 'teaching-session-1');
  assert.equal(events[0].title, 'Algorithms · LZ01');
  assert.equal(events[0].location, 'A1301 · ASM');
  assert.equal(normalizeEvents(events, 'https://socs1.binus.ac.id/messier/')[0].start, '2026-11-19T08:20:00.000Z');
});

test('Messier rejects malformed sessions and accepts explicit empty service results', () => {
  assert.deepEqual(teachingEvents([]), []);
  assert.throws(() => teachingEvents([{ course: { Id: 'c', Subject: 'Algorithms' }, details: [{ Id: 's', Date: null, Shift: '09:00-11:00' }] }]));
  assert.throws(() => teachingEvents([{ course: { Id: 'c', Subject: 'Algorithms' }, details: null }]));
});

test('Messier exam proctor rows retain actual dates, IDs, and class links', async () => {
  const { examEvents } = await import('../adapters/messier.mjs');
  const events = examEvents([{ Id: 'exam-1', Subject: 'Algorithms', ClassName: 'BN11 ',
    Date: '2026-12-21T17:00:00.000Z', Shift: '13:20 - 15:00', Room: 'A1701' }]);
  assert.equal(events[0].id, 'exam-exam-1');
  assert.equal(events[0].start, '2026-12-22T13:20:00+07:00');
  assert.equal(events[0].title, 'Exam proctor · Algorithms · BN11');
  assert.match(events[0].url, /Exam%20Proctor%20Schedule$/);
  assert.deepEqual(examEvents([]), []);
  assert.throws(() => examEvents(null));
});
