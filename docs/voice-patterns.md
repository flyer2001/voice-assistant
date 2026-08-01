---
version: 1.0.0
bumped: 2026-08-01
bumped_reason: "sanity-check на реальных данных: preconditions, test-filter, битый путь transcripts"
---

# Voice pattern analysis — Phase 6 F5 spec

On-demand analysis of войс-запросов от Sergey за N дней. Zero infra в
prod — всё on-request через subagent. Output — markdown report в
`bench/analytics/voice-patterns-YYYY-MM-DD.md`.

## Preconditions — когда запуск имеет смысл

**Проверено 2026-08-01 на живом `audit.jsonl`: запускать пока рано.**

Состояние корпуса на тот момент — 26 записей за 6 недель (2026-06-22 →
2026-08-01), из них 21 success. Топ-униграммы: «сообщение» ×10,
«тестовое» ×7, «проверка» ×5, «напиши» ×5, «ответь» ×5. То есть корпус
целиком состоит из тестовых прогонов, реальных рабочих запросов нет.
На таком объёме «топ-30 униграмм» и порог `count ≥5` дают шум, а не
intents.

Перед запуском проверить:

```bash
python3 - <<'EOF'
import json
es=[json.loads(l) for l in open('/var/lib/voice-bot/audit.jsonl') if l.strip()]
ok=[e for e in es if e.get('outcome')=='success']
print(f"success={len(ok)}  (нужно >=100 нетестовых)")
EOF
```

- **< 100 нетестовых success-записей → не запускать.** Отчёт будет про
  то, как мы тестировали бота.
- Analyzer **обязан** отбрасывать тестовые сообщения: транскрипт
  содержит «тестовое», «проверка связи», «просто ответь», «раз два три»,
  «проверяем функционал» — и сообщать в header, сколько отброшено.

## Trigger

Sergey голосом или в chat: «voice patterns week», «/voice-patterns 30d»,
«что я чаще всего спрашиваю», «pattern report за месяц».

Скрипта нет. Главная сессия spawn'ит Explore-subagent с prompt
template ниже.

## Input sources

### 1. `/var/lib/voice-bot/audit.jsonl` (definitive)

Одна строка на handled voice msg. Schema:

```json
{
  "ts": "2026-07-05T10-15-33.442Z",
  "msg_id": 12345,
  "peer_id": 360258728,
  "audio_path": "/var/lib/voice-bot/raw/…-msg12345.ogg",
  "duration_s": 8,
  "transcript_vk": "...VK auto-transcript...",
  "transcript_whisper": "...Whisper transcript...",
  "decision": "used_vk|used_whisper|drop_*|error_*",
  "stt_ms": 1200,
  "inject_ms": 3400,
  "vk_send_ms": 200,
  "total_ms": 4800,
  "happy_reply_chars": 420,
  "outcome": "success|error|dropped",
  "target_cwd": "/root/projects/cashflow",
  "focus_source": "focus|default|fallback_no_focus|fallback_cwd_missing|fallback_session_offline"
}
```

Older entries могут не иметь `target_cwd` / `focus_source` (pre-Phase 6).
Analyzer treats missing = "default".

### 2. Claude session transcripts (optional, для tool-call overhead)

Live path: `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`.

⚠️ 2026-08-01: в спеке был путь `<encoded-cwd>/history/*.jsonl` — каталога
`history/` не существует ни в одном проекте, глоб возвращал пусто и секция
молча пропускалась. Файлы лежат плоско, имя = session uuid.

Correlation через `ts` ±30s + `target_cwd`. Optional join — если session
transcripts недоступны, пропустить section "dispatcher tool-call overhead".

### 3. Raw .ogg files

`/var/lib/voice-bot/raw/*-msg<id>.ogg` — сохраняются для re-transcribe.
Analyzer НЕ трогает audio, только уже-transcript'ы из audit.jsonl.

## Output format

`bench/analytics/voice-patterns-YYYY-MM-DD.md`, sections:

### Header

- Window: N days (from ts_start to ts_end)
- Total handled: N msgs, из них отброшено как тестовые: M
- Success rate: N% (outcome=success / total)
- Median total_ms. **p95 только при N ≥ 100** — иначе median + min/max,
  p95 на двух десятках записей это просто второй по величине выброс
  (на корпусе 2026-08-01: median 2019ms при max 27658ms)

### Top n-grams (unigrams + bigrams + trigrams)

Топ-30 unigrams, топ-20 bigrams, топ-10 trigrams (stopwords stripped —
«и», «а», «что», «как», «это», «мне», «мы», «ты», «в», «на», «по», «с»).
Source: `transcript_whisper` if present, else `transcript_vk`.

Format:
```
| rank | phrase | count | example msg_id |
```

### Verb frequencies

Список глаголов (heuristic: слова, кончающиеся на `ать|ить|уть|еть|ти`
или начинающиеся с «покажи», «сделай», «открой», «поищи», «найди»,
«запусти», «проверь», «закоммить», «pushни»). Топ-20.

Cel: найти repeating intents для v0.3 canned shortcuts.

### Project mentions

Регекс на имена проектов (grep `/root/projects/*` для списка + hardcoded
aliases: cashflow, voice, assistant, ru_stellar, myRep, agentops).
Матчит basename + русские варианты («кэшфлоу», «войс» и т.д.).

Format:
```
| project | mentions | avg total_ms | success % |
```

### Focus events

Cross-tab `focus_source` × outcome:
```
| focus_source            | count | success% | avg total_ms |
| focus                   |   45  | 96%      | 4200         |
| default                 |  120  | 92%      | 5100         |
| fallback_session_offline|    3  | 100%     | 5300         |
| fallback_no_focus       |    0  | -        | -            |
```

Cel: verify F1/F2 работает, поймать «часто fallback» → focus.json
не обновляется правильно.

**Missing ≠ default.** Записи до Phase 6 не имеют поля вовсе (15 из 26 на
2026-08-01). Сваливать их в `default` — врать: получится «default 15,
focus 7» там, где routing тогда просто не существовало. Отдельная строка
`pre-phase6 (поле отсутствует)`, в проценты success не мешать.

### Bad transcriptions (heuristic)

Кандидаты «плохой расшифровки» — грубая эвристика (analyzer НЕ переслушивает audio):
- ~~`transcript_whisper` ≠ `transcript_vk` и оба ≥5 chars и Jaro <0.6~~
  **Выброшено 2026-08-01.** `transcript_vk` заполнен в 0 из 26 записей.
  Проверено через `messages.getById` на 6 сообщениях (включая июньское):
  в `audio_message` поля `transcript` нет вовсе, `transcript_state` = nil —
  VK не отдаёт свою STT по group-токену. Не реализовывать Jaro/Levenshtein:
  сравнивать не с чем. Подробности — комментарий в `TranscriptDecider.swift`
- Пустой transcript при `duration_s >2s` (Whisper завалился)
- Слова «непонятно / что-то / хз / не расслышал» (Sergey сам подтвердил)

Топ-20 с `msg_id` + `audio_path` для manual re-listen.

### Dispatcher tool-call overhead per intent (optional section)

Если session transcripts joined:
- Group by intent-cluster (по verb + object bigram)
- Средний tool_call_count / inject → total_ms

Показывает: «на «покажи tasks» dispatcher делает 4 tool calls avg,
5s response» → candidate for v0.3 canned shortcut «покажи tasks» →
`cat .claude/TASKS.md`.

Если session transcripts недоступны — skip section, note в header
"session join skipped: transcripts not found".

### Canned shortcut candidates (v0.3 backlog)

Финальный список: intent phrases с `count ≥5` за window и total_ms
среднее >3000ms → «candidate for v0.3 regex shortcut».

Format:
```
- «покажи tasks» (12 mentions, avg 4800ms) → регекс `покажи (.+) tasks`
  → route direct `cat .claude/TASKS.md` в matched project cwd
```

## Subagent prompt template

Spawn Explore-subagent (read-only OK). Prompt:

```
Analyze voice bot patterns за последние N дней.

Input:
- Read /var/lib/voice-bot/audit.jsonl (JSONL, одна запись на handled voice msg).
- Filter by ts >= now - N days.
- Optional: если Bash доступен, glob ~/.claude/projects/*/history/*.jsonl
  и join через target_cwd + ts ±30s для tool-call overhead section.
  Если нет — skip section, note в header.

Output:
- Один markdown file /root/projects/voice/bench/analytics/voice-patterns-YYYY-MM-DD.md
  (YYYY-MM-DD = сегодня).
- Sections per spec docs/voice-patterns.md: Header, Top n-grams
  (uni+bi+trigrams), Verb frequencies, Project mentions, Focus events,
  Bad transcriptions, [optional] Dispatcher overhead, Canned shortcut candidates.

Rules:
- Русский stopword list см. spec.
- N-gram tokens lowercased, punctuation stripped.
- Bad transcription heuristic — Levenshtein / Jaro implement inline
  (не тянуть pip / npm deps).
- Ссылки на msg_id для примеров.

Спец полностью: /root/projects/voice/docs/voice-patterns.md
```

## Rate / freshness

Sergey запускает **on-demand**, не крон. Report timestamp'ится, старые
не удаляются автоматически. Если >20 отчётов в `bench/analytics/` —
предложить cleanup.

## Non-goals

- **Realtime alerting.** Нет. Только post-hoc.
- **Auto-generation shortcuts.** Analyzer только предлагает —
  реализация shortcut'а руками (v0.3).
- **Cross-user analytics.** Sergey-only (peer_id=360258728). Fixed
  MVP scope.
- **Fixed schedule.** Sergey захочет — Sergey запустит.

## Related

- audit.jsonl schema — `backend/voice-service/Sources/VKAdapter/AudioStorage.swift`
- Focus state — `backend/voice-service/Sources/VoiceServiceCore/FocusState.swift`
- v0.3 intent shortcuts backlog — [`.claude/BACKLOG.md`](../.claude/BACKLOG.md)
- STT-качество, откуда берутся плохие транскрипты —
  [whisper-benchmark-plan.md](whisper-benchmark-plan.md)

[← docs/INDEX.md](INDEX.md)
