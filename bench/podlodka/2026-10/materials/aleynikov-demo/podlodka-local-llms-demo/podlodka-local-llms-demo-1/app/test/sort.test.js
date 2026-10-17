import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { sortByStarsDesc } from '../lib/sort.mjs';

const fixture = JSON.parse(
  readFileSync(fileURLToPath(new URL('./fixtures/search_response.json', import.meta.url)), 'utf8')
);

test('sortByStarsDesc упорядочивает фикстуру по убыванию звёзд', () => {
  const sorted = sortByStarsDesc(fixture.items);
  assert.deepEqual(sorted.map((i) => i.stargazers_count), [900, 250, 40]);
  assert.deepEqual(sorted.map((i) => i.full_name), ['bob/beta', 'acme/alpha', 'eve/gamma']);
});

test('sortByStarsDesc не мутирует исходный массив', () => {
  const before = fixture.items.map((i) => i.stargazers_count);
  sortByStarsDesc(fixture.items);
  assert.deepEqual(fixture.items.map((i) => i.stargazers_count), before);
});
