import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const collectPath = fileURLToPath(new URL('../collect.mjs', import.meta.url));

test('collect.mjs без GITHUB_TOKEN: ненулевой код возврата и сообщение про GITHUB_TOKEN (без сети)', () => {
  const env = { ...process.env };
  delete env.GITHUB_TOKEN; // реальный секрет в дочерний процесс не передаётся
  const res = spawnSync(process.execPath, [collectPath], { env, encoding: 'utf8', timeout: 20000 });
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /GITHUB_TOKEN/);
});
