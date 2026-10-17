// Точка входа Node: собирает дайджест и пишет out/state.json.
// Секрет берётся только из process.env.GITHUB_TOKEN; токен не печатается.
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { dateSevenDaysAgo } from './lib/date.mjs';
import { buildSearchUrl, queryText } from './lib/query.mjs';
import { createQueue } from './lib/queue.mjs';
import { sortByStarsDesc } from './lib/sort.mjs';
import { writeState } from './lib/state.mjs';
import { writeSessionFile } from './lib/session.mjs';

const STATE_PATH = fileURLToPath(new URL('../out/state.json', import.meta.url));
const SESSION_PATH = fileURLToPath(new URL('./session.js', import.meta.url));

function mapItem(item) {
  return {
    full_name: item.full_name,
    html_url: item.html_url,
    description: item.description ?? null,
    stargazers_count: item.stargazers_count,
    forks_count: item.forks_count,
    open_issues_count: item.open_issues_count,
    language: item.language ?? null,
    created_at: item.created_at,
    updated_at: item.updated_at,
    pushed_at: item.pushed_at,
    owner_login: item.owner?.login ?? null,
    owner_avatar_url: item.owner?.avatar_url ?? null,
    topics: Array.isArray(item.topics) ? item.topics : [],
    license_spdx_id: item.license?.spdx_id ?? null,
  };
}

async function main() {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.error(
      'Не задана переменная среды GITHUB_TOKEN. Задайте её, например: ' +
      '$env:GITHUB_TOKEN = "<токен>"'
    );
    process.exit(1);
  }

  const d7 = dateSevenDaysAgo(new Date());
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  const queue = createQueue();
  const freshData = await queue.enqueue(buildSearchUrl('fresh', d7), headers);
  const updatedData = await queue.enqueue(buildSearchUrl('updated', d7), headers);

  const fresh = sortByStarsDesc(freshData.items ?? []).slice(0, 12).map(mapItem);
  const updated = sortByStarsDesc(updatedData.items ?? []).slice(0, 12).map(mapItem);

  const state = {
    generated_at: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    since: d7,
    queries: { fresh: queryText('fresh', d7), updated: queryText('updated', d7) },
    fresh,
    updated,
  };

  await writeState(STATE_PATH, state);
  // Генерируемый артефакт для браузера: app/session.js (секрет, не коммитить).
  await writeSessionFile(SESSION_PATH, token, state.generated_at);
  console.log(
    `OK: out/state.json записан; fresh=${fresh.length}, updated=${updated.length}, since=${d7}; app/session.js обновлён`
  );
}

main().catch((err) => {
  console.error(`Ошибка сбора дайджеста: ${err.message}`);
  process.exit(1);
});
