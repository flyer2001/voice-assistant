// Единая последовательная очередь внешних запросов + retry для 403/429.
// fetch инъектируется (по умолчанию глобальный) — для тестов без сети.

export function retryDelayMs(res, nowMs) {
  const get = res && res.headers && typeof res.headers.get === 'function'
    ? (name) => res.headers.get(name)
    : () => null;
  const retryAfter = get('Retry-After') ?? get('retry-after');
  if (retryAfter !== null && retryAfter !== undefined && String(retryAfter).trim() !== '') {
    const s = Number(retryAfter);
    if (Number.isFinite(s)) return Math.max(0, s * 1000);
  }
  const reset = get('X-RateLimit-Reset') ?? get('x-ratelimit-reset');
  if (reset !== null && reset !== undefined && String(reset).trim() !== '') {
    const r = Number(reset);
    if (Number.isFinite(r)) return Math.max(0, r * 1000 - nowMs);
  }
  return 1000; // запасная пауза, если заголовков нет
}

export function createQueue({
  fetchFn = globalThis.fetch,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  now = () => Date.now(),
  maxRetries = 3,
} = {}) {
  let chain = Promise.resolve();

  async function runOne(url, headers) {
    let retries = 0;
    for (;;) {
      const res = await fetchFn(url, { headers });
      if (res.status === 403 || res.status === 429) {
        if (retries >= maxRetries) {
          throw new Error(
            `Превышен лимит запросов GitHub (HTTP ${res.status}), ретраи исчерпаны`
          );
        }
        retries += 1;
        await sleep(retryDelayMs(res, now()));
        continue;
      }
      if (!res.ok) {
        throw new Error(`GitHub API вернул HTTP ${res.status}`);
      }
      return res.json();
    }
  }

  function enqueue(url, headers) {
    // строго по одному: цепочка промисов
    const result = chain.then(
      () => runOne(url, headers),
      () => runOne(url, headers)
    );
    chain = result.then(
      () => undefined,
      () => undefined
    );
    return result;
  }

  return { enqueue };
}
