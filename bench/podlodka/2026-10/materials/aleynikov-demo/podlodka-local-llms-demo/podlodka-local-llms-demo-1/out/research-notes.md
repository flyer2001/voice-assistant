# Research notes — дайджест трендов GitHub (тема multi-agent)

Дата research: 2026-10-14. Граница «последних 7 дней»: `2026-10-07` (today − 7 дней, формат `YYYY-MM-DD`).
Источники: official docs (docs.github.com) + фактические запросы к api.github.com с токеном из `$env:GITHUB_TOKEN`.
Сырые ответы API сохранены рядом: `out/rate_limit.json`, `out/search_created.json`, `out/search_pushed.json`, `out/graphql_created_sample.json`.

## 1. Эндпоинты и параметры поиска (подтверждено docs.github.com/en/rest/search/search + фактическими запросами)

Эндпоинт: `GET https://api.github.com/search/repositories`

Query-параметры (из официальной схемы параметров):
- `q` (string, required) — keywords + qualifiers, URL-encode (`encodeURIComponent`).
- `sort` — один из `stars`, `forks`, `help-wanted-issues`, `updated`. Default: best match.
- `order` — `desc` | `asc` (default `desc`); игнорируется без `sort`.
- `per_page` — integer, max 100, default 30. Нам нужно 12 → `per_page=12`.
- `page` — integer, default 1.
- Ограничения: до 100 результатов на страницу, максимум 1000 результатов на поиск; search scope — до 4000 репозиториев; запрос длиннее 256 символов (без qualifiers) → 422.

Search-квалификаторы (docs.github.com/en/search-github/searching-on-github/searching-for-repositories):
- `created:>=YYYY-MM-DD` — дата создания репозитория; формат ISO8601 `YYYY-MM-DD`, опционально `THH:MM:SS+00:00`; поддерживаются `>`, `>=`, `<`, `<=`, диапазон `a..b`.
- `pushed:>=YYYY-MM-DD` — последний push (самый свежий коммит на любой ветке) — это и есть «обновлённые».
- `topic:multi-agent` — репозитории, помеченные topic «multi-agent».
- Текстовый match без qualifier (`multi-agent created:...`) ищет по name, description и topics (qualifier `in` по умолчанию = name+description+topics; `in:topics`, `in:name`, `in:description`, `in:readme` — сужают).
- Форки по умолчанию исключены; при необходимости `fork:true` / `fork:only`.

### Проверенные вызовы (фактический HTTP-код 200, см. п.3)

Категория «свежие» (созданные за 7 дней), сортировка по убыванию звёзд:
```
GET https://api.github.com/search/repositories?q=topic%3Amulti-agent+created%3A%3E%3D2026-10-07&sort=stars&order=desc&per_page=12
```
(q после декодирования: `topic:multi-agent created:>=2026-10-07`)

Категория «изменения» (pushed за 7 дней):
```
GET https://api.github.com/search/repositories?q=topic%3Amulti-agent+pushed%3A%3E%3D2026-10-07&sort=stars&order=desc&per_page=12
```

В JS строить так: `'q=' + encodeURIComponent('topic:multi-agent created:>=' + d7)` где `d7` — дата (today − 7 дней) в `YYYY-MM-DD`.
Сортировка `sort=stars&order=desc` уже даёт «по убыванию звёзд» на стороне API — дополнительная сортировка не обязательна, но не вредит.

## 2. Поля ответа (схема «Repo Search Result Item» из docs + проверено в фактических JSON)

Корень ответа: `total_count` (int), `incomplete_results` (bool), `items` (array).

В каждом item (имена полей точные):
- `id` (int), `node_id`, `name`, `full_name`, `private`
- `owner` (объект): `login`, `id`, `avatar_url` ← аватар для карточки, `html_url`, `type` (`User`|`Organization`), `gravatar_id` и др.
- `html_url` (ссылка на репозиторий), `description` (string|null), `fork`
- `url` (API-URL репозитория)
- `created_at`, `updated_at`, `pushed_at` — ISO 8601 (`2026-10-07T15:37:36Z`)
- `homepage` (string|null), `size` (KB)
- `stargazers_count`, `watchers_count`, `watchers`, `forks_count`, `forks`, `open_issues_count`, `open_issues`
- `language` (string|null), `default_branch`, `master_branch` (опц.)
- `score` (number), `topics` (array of string)
- `license` (null|{`key`,`name`,`url`,`spdx_id`,`node_id`}), `archived`, `disabled`, `visibility`
- `permissions` ({admin,maintain,push,triage,pull}), `has_issues`, `has_wiki`, `has_pages`, `has_projects`
- десятки template-URL полей (`forks_url`, `issues_url` и т.п.) — для дайджеста не нужны.

Аватар в карточке: `owner.avatar_url` (например `https://avatars.githubusercontent.com/u/279467036?v=4`). Отдельного «аватара репозитория» в API нет — используется аватар владельца.

## 3. Аутентификация и фактические проверки (ГЛАВНОЕ: всё ниже — реальные выводы команд)

Заголовки (из docs): `Authorization: Bearer <token>` (рекомендуемый), также исторически принимается `Authorization: token <token>`; `Accept: application/vnd.github+json`; опционально `X-GitHub-Api-Version: 2022-11-28`.

### Факт: GITHUB_TOKEN установлен и валиден
Команда (PowerShell; `curl` — алиас Invoke-WebRequest в этой системе; значение токена НЕ выводилось):
```powershell
curl "https://api.github.com/rate_limit" -Headers @{Authorization="Bearer $env:GITHUB_TOKEN"} -UseBasicParsing -OutFile "out\rate_limit.json"
```
Вывод: команда завершилась без ошибки (IWR бросает исключение на не-2xx ⇒ HTTP 200). В `out/rate_limit.json`:
`"search":{"limit":30,"used":0,"remaining":30}` и `"core":{"limit":5000,...}` — ответы с аутентифицированными лимитами ⇒ токен существует и принят.
Длина токена намеренно не выводилась: политика безопасности среды запретила конструировать команду, печатающую что-либо, вычисленное из значения переменной (только одиночные `curl`-команды без конвейеров). Факт наличия подтвержен сильнее — валидацией на сервере GitHub (200 + лимит 5000 + заголовок ответа `github-authentication-token-expiration: 2026-11-02 04:44:45 UTC`).

### Факт: тестовый Search API с токеном (HTTP-код и данные)
Команда:
```powershell
curl "https://api.github.com/search/repositories?q=topic%3Amulti-agent+created%3A%3E%3D2026-10-07&sort=stars&order=desc&per_page=12" -Headers @{Authorization="Bearer $env:GITHUB_TOKEN"; Accept="application/vnd.github+json"} -UseBasicParsing
```
Вывод консоли: `StatusCode : 200`, `StatusDescription : OK`, `RawContentLength : 71659`, в Content: `{"total_count":670,"incomplete_results":false,...}`.
Ответ содержал `Link: ...&page=2>; rel="next", ...&page=56>; rel="last"` (пагинация).

- Категория «свежие» (`created:>=2026-10-07`): HTTP 200, **total_count = 670** (полный ответ: `out/search_created.json`).
- Категория «изменения» (`pushed:>=2026-10-07`): HTTP 200 (без исключений), **total_count = 3462** (полный ответ: `out/search_pushed.json`). Первый элемент: `paperclipai/paperclip` — «The open-source app everyone uses to manage agents at work», owner type `Organization`.

Примеры реальных репозиториев категории «свежие» (топ-2 по звёздам, получены GraphQL-срезом того же запроса, `out/graphql_created_sample.json`):
- `Fei2411/DeepSeek-Bot` — 1857 звёзд, created_at `2026-10-07T15:37:36Z`, pushed_at `2026-10-14T16:29:19Z`, avatar `https://avatars.githubusercontent.com/u/279467036?...`
- `SouravBeraAkaSpeed/xiryn` — 170 звёзд, created_at `2026-10-11T13:12:31Z`.
(`repositoryCount` в GraphQL = 670–671 совпал с REST `total_count` — данные согласованы.)

### Важное ограничение токена (факт)
Токен — fine-grained PAT с урезанными правами: GraphQL `stargazers` (connection) вернул `FORBIDDEN "Resource not accessible by personal access token"`; scalar `stargazerCount` и REST `stargazers_count` работают. Вывод для реализации: **использовать только REST Search API**, не GraphQL.

## 4. Запуск HTML-страницы без сервера (file://)

- `fetch()` из страницы, открытой по `file://`, к `https://api.github.com`: GitHub REST API поддерживает CORS (заголовок `Access-Control-Allow-Origin: *`), запросы с токеном из браузера к api.github.com штатно работают. Кастомный заголовок `Authorization` вызывает CORS-preflight `OPTIONS` — GitHub его обрабатывает. Пункт для обязательной проверки на стадии реализации (в этой среде браузер недоступен; заголовок CORS в сохранённых ответах не фиксировался).
- Переменная окружения `GITHUB_TOKEN` недоступна из браузера при открытии файла. Выбранный надёжный вариант: **поле ввода токена на странице** (`<input type="password">`): пользователь один раз вставляет токен (в README описать, как посмотреть `$env:GITHUB_TOKEN` в PowerShell: `$env:GITHUB_TOKEN`); токен хранится только в памяти JS-модуля (переменная), не пишется в localStorage/sessionStorage/URL, не попадает в console.log; после перезагрузки страницы вводить заново. Это удовлетворяет «не вшивай токен в код и не логируй».
- Альтернатива `prompt()` — хуже (нельзя сделать masked, значение видно в истории консоли при ошибках). Не использовать.
- Дата «7 дней назад» вычисляется в рантайме страницы: `new Date(Date.now() - 7*86400000)` → `YYYY-MM-DD` (UTC). Не хардкодить 2026-10-07.
- Node.js 20+ (для тестов/скриптов вне страницы, если понадобятся): глобальный `fetch` без флагов, `node:test` + `node:assert` из коробки, `node:fs/promises` (`readFile`, `writeFile`). `node --test` запускает тесты без npm.

## 5. Rate limits (подтверждено docs + /rate_limit)

- Search API: **аутентифицированно — 30 запросов/минуту** (факт из `out/rate_limit.json`: `search.limit=30`); неаутентифицированно — 10 запросов/минуту. Search code — 10/мин (не используется).
- Core API: 5000/час (аутентифицированно; факт: `core.limit=5000`).
- Приложения: всего 2 запроса на показ дайджеста — лимит не проблема. Повторные запросы: при `403`/`429` читать `X-RateLimit-Remaining`, `X-RateLimit-Reset` (unix-секунды) и `Retry-After`; не поллить. При `incomplete_results: true` — результат усечён таймаутом, можно повторить позже.
- Ошибки search: `422` Validation failed (плохой запрос), `401` (нет/плохой токен — фактически получили 401 при некорректном заголовке), `403` (лимит/анти-спам).

## 6. Чек-лист требований задачи → как закрыты
- 2 категории по 12: два запроса с `per_page=12` (см. URL в п.1). ✓ total_count 670 и 3462 — по 12 наберётся.
- Ранжирование по звёздам: `sort=stars&order=desc`. ✓
- Аватары: `owner.avatar_url`. ✓
- Токен из env: в браузере env недоступен → поле ввода (п.4), в README показать команду чтения env. ✓ (компромисс зафиксировать в README)
- Без npm, один html: fetch + vanilla JS. ✓
- Прогресс загрузки, 2 темы, карточки 3 в ряд по центру, раскрытие в карточке — UI, требований к API нет.
