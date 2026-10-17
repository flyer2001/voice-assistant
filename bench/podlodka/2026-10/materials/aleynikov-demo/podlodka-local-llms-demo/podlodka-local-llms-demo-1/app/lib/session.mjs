// Генерация сессионного файла app/session.js (ГЕНЕРИРУЕМЫЙ АРТЕФАКТ ДАННЫХ, содержит секрет).
// Сам модуль токена не содержит — значение приходит параметром из env.
import { writeFile } from 'node:fs/promises';

export const SESSION_MAX_AGE_MS = 24 * 3600 * 1000; // 24 часа

// JSON.stringify экранирует всё, что нужно; заворачиваем в присваивание window-глобалу.
export function sessionFileContent(token, generatedAt) {
  return 'window.__GH_SESSION = ' +
    JSON.stringify({ token: token, generated_at: generatedAt }) + ';\n';
}

export function isSessionFresh(generatedAt, nowMs = Date.now()) {
  const t = Date.parse(generatedAt);
  if (!Number.isFinite(t)) return false;
  const age = nowMs - t;
  return age >= 0 && age <= SESSION_MAX_AGE_MS;
}

export async function writeSessionFile(filePath, token, generatedAt = new Date().toISOString()) {
  await writeFile(filePath, sessionFileContent(token, generatedAt), 'utf8');
  return filePath;
}
