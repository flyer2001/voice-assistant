// Дата границы «последние 7 дней» (UTC, today − 7 дней) в формате YYYY-MM-DD.
export function dateSevenDaysAgo(now = new Date()) {
  const d = new Date(now.getTime() - 7 * 86400000);
  return d.toISOString().slice(0, 10);
}
