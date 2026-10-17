import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { writeSessionFile, sessionFileContent, isSessionFresh } from '../lib/session.mjs';

test('writeSessionFile: файл содержит window.__GH_SESSION с token/generated_at и это валидный JS', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'digest-session-'));
  try {
    const file = join(dir, 'session.js');
    const generatedAt = '2026-10-14T12:00:00Z';
    await writeSessionFile(file, 'FIXED', generatedAt);
    const content = await readFile(file, 'utf8');
    assert.ok(content.includes('window.__GH_SESSION'));
    assert.ok(content.includes('"token"'));
    assert.ok(content.includes('"generated_at"'));
    assert.ok(content.includes('FIXED'));
    // валидный JS: выполняем в изолированном "window" и проверяем объект
    const fakeWindow = {};
    new Function('window', content)(fakeWindow); // бросит SyntaxError, если JS невалиден
    assert.equal(fakeWindow.__GH_SESSION.token, 'FIXED');
    assert.equal(fakeWindow.__GH_SESSION.generated_at, generatedAt);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('sessionFileContent экранирует спецсимволы токена через JSON.stringify', () => {
  const content = sessionFileContent('a"b\\c<>&', '2026-10-14T12:00:00Z');
  const fakeWindow = {};
  new Function('window', content)(fakeWindow);
  assert.equal(fakeWindow.__GH_SESSION.token, 'a"b\\c<>&');
});

test('isSessionFresh: свежая сессия — true, старше 24 часов — false, мусор — false', () => {
  const now = Date.parse('2026-10-14T12:00:00Z');
  assert.equal(isSessionFresh('2026-10-14T12:00:00Z', now), true);
  assert.equal(isSessionFresh('2026-10-13T13:00:00Z', now), true);  // 23 часа
  assert.equal(isSessionFresh('2026-10-13T11:59:59Z', now), false); // 24ч + 1 сек
  assert.equal(isSessionFresh('2026-10-12T12:00:00Z', now), false); // 48 часов (устаревшая)
  assert.equal(isSessionFresh('не дата', now), false);
  assert.equal(isSessionFresh(undefined, now), false);
});
