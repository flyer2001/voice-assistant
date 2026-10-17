import test from 'node:test';
import assert from 'node:assert/strict';
import { createQueue } from '../lib/queue.mjs';

function fakeResponse({ status, ok, body = {}, headers = {} }) {
  return {
    status,
    ok,
    headers: {
      get: (name) => {
        for (const [k, v] of Object.entries(headers)) {
          if (k.toLowerCase() === String(name).toLowerCase()) return String(v);
        }
        return null;
      },
    },
    json: async () => body,
  };
}

test('403 с Retry-After, затем 200: два выполнения, результат получен', async () => {
  let calls = 0;
  const sleeps = [];
  const q = createQueue({
    fetchFn: async () => {
      calls += 1;
      if (calls === 1) {
        return fakeResponse({ status: 403, ok: false, headers: { 'Retry-After': '1' } });
      }
      return fakeResponse({ status: 200, ok: true, body: { total_count: 1 } });
    },
    sleep: async (ms) => { sleeps.push(ms); },
  });
  const result = await q.enqueue('https://api.github.com/x', {});
  assert.deepEqual(result, { total_count: 1 });
  assert.equal(calls, 2);
  assert.deepEqual(sleeps, [1000]);
});

test('429 без Retry-After, с X-RateLimit-Reset: пауза по reset', async () => {
  const nowMs = 1_760_000_000_000;
  const resetSec = Math.floor(nowMs / 1000) + 5;
  let calls = 0;
  const sleeps = [];
  const q = createQueue({
    fetchFn: async () => {
      calls += 1;
      if (calls === 1) {
        return fakeResponse({ status: 429, ok: false, headers: { 'X-RateLimit-Reset': resetSec } });
      }
      return fakeResponse({ status: 200, ok: true, body: { ok: true } });
    },
    sleep: async (ms) => { sleeps.push(ms); },
    now: () => nowMs,
  });
  const result = await q.enqueue('https://api.github.com/x', {});
  assert.deepEqual(result, { ok: true });
  assert.equal(calls, 2);
  assert.equal(sleeps.length, 1);
  assert.equal(sleeps[0], resetSec * 1000 - nowMs);
});

test('Постоянные 403 без заголовков: ровно 3 ретрая (4 попытки), затем ошибка', async () => {
  let calls = 0;
  const q = createQueue({
    fetchFn: async () => {
      calls += 1;
      return fakeResponse({ status: 403, ok: false });
    },
    sleep: async () => {},
  });
  await assert.rejects(() => q.enqueue('https://api.github.com/x', {}), /лимит/i);
  assert.equal(calls, 4); // 1 начальная попытка + 3 ретрая
});

test('401: без ретрая, одна попытка, ошибка', async () => {
  let calls = 0;
  const q = createQueue({
    fetchFn: async () => {
      calls += 1;
      return fakeResponse({ status: 401, ok: false });
    },
    sleep: async () => {},
  });
  await assert.rejects(() => q.enqueue('https://api.github.com/x', {}), /401/);
  assert.equal(calls, 1);
});

test('Очередь последовательная: запросы исполняются строго по одному', async () => {
  let active = 0;
  let maxActive = 0;
  const q = createQueue({
    fetchFn: async () => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((r) => setTimeout(r, 5));
      active -= 1;
      return fakeResponse({ status: 200, ok: true, body: { ok: true } });
    },
  });
  await Promise.all([
    q.enqueue('https://api.github.com/a', {}),
    q.enqueue('https://api.github.com/b', {}),
    q.enqueue('https://api.github.com/c', {}),
  ]);
  assert.equal(maxActive, 1);
});
