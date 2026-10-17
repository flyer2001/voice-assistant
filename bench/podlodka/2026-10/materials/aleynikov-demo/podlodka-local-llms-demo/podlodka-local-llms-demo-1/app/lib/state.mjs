// Чтение/валидация/запись out/state.json (курсоры: generated_at, since, queries).
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export function validateState(obj) {
  if (!obj || typeof obj !== 'object') throw new Error('state: не объект');
  if (typeof obj.generated_at !== 'string' || !obj.generated_at) {
    throw new Error('state: нет generated_at');
  }
  if (typeof obj.since !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(obj.since)) {
    throw new Error('state: нет корректного since (YYYY-MM-DD)');
  }
  if (!obj.queries || typeof obj.queries !== 'object') {
    throw new Error('state: нет queries');
  }
  if (!Array.isArray(obj.fresh)) throw new Error('state: нет массива fresh');
  if (!Array.isArray(obj.updated)) throw new Error('state: нет массива updated');
  return obj;
}

export async function writeState(filePath, state) {
  validateState(state);
  await mkdir(dirname(filePath), { recursive: true });
  await writeFile(filePath, JSON.stringify(state, null, 2) + '\n', 'utf8');
  return state;
}

export async function readState(filePath) {
  const raw = await readFile(filePath, 'utf8');
  return validateState(JSON.parse(raw));
}
