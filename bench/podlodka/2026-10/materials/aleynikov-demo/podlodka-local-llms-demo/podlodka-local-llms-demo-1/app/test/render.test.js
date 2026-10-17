import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { renderCard, renderSection, escapeHtml } from '../lib/render.mjs';

const fixture = JSON.parse(
  readFileSync(fileURLToPath(new URL('./fixtures/search_response.json', import.meta.url)), 'utf8')
);

test('renderCard содержит full_name, звёзды и аватар в <img src>', () => {
  const item = fixture.items[0];
  const html = renderCard(item);
  assert.ok(html.includes('acme/alpha'));
  assert.ok(html.includes('250'));
  assert.ok(html.includes('<img'));
  assert.ok(html.includes('src="https://avatars.githubusercontent.com/u/11?v=4"'));
});

test('renderCard экранирует HTML-спецсимволы описания', () => {
  const html = renderCard(fixture.items[0]);
  // описание: Multi-agent <framework> & "orchestrator"
  assert.ok(html.includes('&lt;framework&gt;'));
  assert.ok(html.includes('&amp;'));
  assert.ok(html.includes('&quot;orchestrator&quot;'));
  assert.ok(!html.includes('<framework>'));
});

test('renderSection для 12 элементов даёт grid-обёртку и 12 карточек (по 3 в ряд через CSS)', () => {
  const items = Array.from({ length: 12 }, (_, i) => ({
    ...fixture.items[i % 3],
    full_name: `org/repo-${i}`,
  }));
  const html = renderSection('Свежие', items);
  assert.ok(html.includes('<div class="grid">'));
  const cardCount = (html.match(/class="card"/g) ?? []).length;
  assert.equal(cardCount, 12);
});

test('escapeHtml экранирует все спецсимволы', () => {
  assert.equal(escapeHtml(`<>&"'`), '&lt;&gt;&amp;&quot;&#39;');
});
