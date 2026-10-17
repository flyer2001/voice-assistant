import test from 'node:test';
import assert from 'node:assert/strict';
import { dateSevenDaysAgo } from '../lib/date.mjs';

test('dateSevenDaysAgo возвращает YYYY-MM-DD ровно на 7 дней раньше (UTC)', () => {
  const now = new Date('2026-10-14T15:30:00Z');
  assert.equal(dateSevenDaysAgo(now), '2026-10-07');

  const now2 = new Date('2026-01-03T00:00:01Z');
  assert.equal(dateSevenDaysAgo(now2), '2025-12-27');

  const out = dateSevenDaysAgo(new Date());
  assert.match(out, /^\d{4}-\d{2}-\d{2}$/);
});
