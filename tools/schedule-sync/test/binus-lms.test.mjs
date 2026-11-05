import test from 'node:test';
import assert from 'node:assert/strict';
import { parseMonth } from '../adapters/binus-lms.mjs';
import { normalizeEvents } from '../core.mjs';

test('LMS uses each class time, Jakarta offset, exam seat and stable IDs', () => {
  const record = { scheduleId: 'session-1', content: 'Example course', title: 'LA01 - LEC',
    dateStart: '2026-11-05T10:00:00', dateEnd: '2026-11-05T11:40:00',
    scheduleType: 'Onsite Exam', lamType: 'MID', location: 'Campus - A101',
    customParam: { seatNumber: '3' }, isCancelled: false };
  const events = normalizeEvents(parseMonth([{ dateStart: '2026-11-05T13:20:00', Schedule: [record] }], '2026-11'), 'https://lms.binus.ac.id');
  assert.deepEqual(events, [{ title: 'Example course · MID exam', start: '2026-11-05T03:00:00.000Z',
    end: '2026-11-05T04:40:00.000Z', location: 'Campus - A101 · Seat 3',
    url: 'https://lms.binus.ac.id/lms/schedule/2026-11', id: 'session-1' }]);
  assert.deepEqual(parseMonth([{ Schedule: [{ ...record, isCancelled: true }] }], '2026-11'), []);
});

test('LMS accepts verified empty response and rejects unknown schedule shapes', () => {
  assert.deepEqual(parseMonth([], '2026-11'), []);
  assert.throws(() => parseMonth({ error: 'unauthorized' }, '2026-11'));
  assert.throws(() => parseMonth([{}], '2026-11'));
  assert.throws(() => parseMonth([{ Schedule: [{}] }], '2026-11'));
});
