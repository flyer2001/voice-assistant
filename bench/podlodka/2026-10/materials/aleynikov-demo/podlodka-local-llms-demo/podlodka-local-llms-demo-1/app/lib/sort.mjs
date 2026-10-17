// Страховочная сортировка по убыванию звёзд (основная — на стороне API).
export function sortByStarsDesc(items) {
  return [...items].sort((a, b) => b.stargazers_count - a.stargazers_count);
}
