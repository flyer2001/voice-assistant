// Рендер карточек в HTML-строку (Node-версия; в index.html — эквивалентная DOM-версия).
// Принимает как item ответа API (owner.avatar_url), так и плоскую запись state.

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function avatarOf(item) {
  if (item.owner_avatar_url) return item.owner_avatar_url;
  if (item.owner && item.owner.avatar_url) return item.owner.avatar_url;
  return '';
}

export function renderCard(item) {
  const name = item.full_name ?? '';
  const avatar = escapeHtml(avatarOf(item));
  const url = escapeHtml(item.html_url ?? '');
  const desc = escapeHtml(item.description ?? '');
  const stars = escapeHtml(item.stargazers_count ?? 0);
  return (
    '<article class="card">' +
    `<img class="avatar" src="${avatar}" alt="Аватар ${escapeHtml(name)}">` +
    `<h3 class="name">${escapeHtml(name)}</h3>` +
    `<p class="desc">${desc}</p>` +
    `<p class="stars">★ ${stars}</p>` +
    `<a class="link" href="${url}" target="_blank" rel="noopener">${url}</a>` +
    '</article>'
  );
}

export function renderSection(title, items) {
  const cards = items.map(renderCard).join('');
  return (
    '<section class="section">' +
    `<h2>${escapeHtml(title)}</h2>` +
    `<div class="grid">${cards}</div>` +
    '</section>'
  );
}
