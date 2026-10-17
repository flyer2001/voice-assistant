import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSearchUrl, queryText } from '../lib/query.mjs';

test('buildSearchUrl fresh содержит закодированный q, sort, per_page=12', () => {
  const url = buildSearchUrl('fresh', '2026-10-07');
  assert.ok(url.startsWith('https://api.github.com/search/repositories?'));
  assert.ok(url.includes('topic%3Amulti-agent'));
  assert.ok(url.includes('created%3A%3E%3D'));
  assert.ok(url.includes('per_page=12'));
  assert.ok(url.includes('sort=stars'));
  assert.ok(url.includes('order=desc'));
});

test('buildSearchUrl updated использует qualifier pushed', () => {
  const url = buildSearchUrl('updated', '2026-10-07');
  assert.ok(url.includes('pushed%3A%3E%3D2026-10-07'));
  assert.ok(!url.includes('created%3A'));
});

test('queryText даёт декодированный запрос', () => {
  assert.equal(queryText('fresh', '2026-10-07'), 'topic:multi-agent created:>=2026-10-07');
  assert.equal(queryText('updated', '2026-10-07'), 'topic:multi-agent pushed:>=2026-10-07');
});
