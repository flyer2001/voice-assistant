// Сборка URL запроса к GitHub Search API (REST-only).
// category: 'fresh' (created:>=d7) | 'updated' (pushed:>=d7).
export function buildSearchUrl(category, d7) {
  const qualifier = category === 'fresh' ? 'created' : 'pushed';
  const q = `topic:multi-agent ${qualifier}:>=${d7}`;
  return (
    'https://api.github.com/search/repositories?q=' +
    encodeURIComponent(q) +
    '&sort=stars&order=desc&per_page=12'
  );
}

export function queryText(category, d7) {
  const qualifier = category === 'fresh' ? 'created' : 'pushed';
  return `topic:multi-agent ${qualifier}:>=${d7}`;
}
