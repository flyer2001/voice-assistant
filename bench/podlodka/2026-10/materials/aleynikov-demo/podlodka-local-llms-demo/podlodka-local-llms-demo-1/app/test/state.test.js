import test from 'node:test';
import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { writeState, readState, validateState } from '../lib/state.mjs';

test('roundtrip: запись state во временный файл и чтение обратно', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'digest-state-'));
  try {
    const file = join(dir, 'state.json');
    const state = {
      generated_at: '2026-10-14T12:00:00Z',
      since: '2026-10-07',
      queries: { fresh: 'topic:multi-agent created:>=2026-10-07', updated: 'topic:multi-agent pushed:>=2026-10-07' },
      fresh: [{ full_name: 'a/b', stargazers_count: 5 }],
      updated: [{ full_name: 'c/d', stargazers_count: 7 }],
    };
    await writeState(file, state);
    const back = await readState(file);
    assert.equal(back.generated_at, '2026-10-14T12:00:00Z');
    assert.equal(back.since, '2026-10-07');
    assert.equal(back.queries.fresh, state.queries.fresh);
    assert.equal(back.queries.updated, state.queries.updated);
    assert.equal(back.fresh.length, 1);
    assert.equal(back.updated.length, 1);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('валидатор отвергает state без since / fresh / updated', () => {
  const good = {
    generated_at: '2026-10-14T12:00:00Z',
    since: '2026-10-07',
    queries: { fresh: 'q1', updated: 'q2' },
    fresh: [],
    updated: [],
  };
  assert.doesNotThrow(() => validateState(good));
  assert.throws(() => validateState({ ...good, since: undefined }));
  assert.throws(() => validateState({ ...good, fresh: undefined }));
  assert.throws(() => validateState({ ...good, updated: undefined }));
  assert.throws(() => validateState({ ...good, fresh: {} }));
});
