# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Каждый пункт исполним сейчас и имеет done-signal. Аспирационное и
> заблокированное железом → [`BACKLOG.md`](BACKLOG.md).
> Закрытые задачи — в [`CHANGELOG.md`](CHANGELOG.md) (prepend через `/endsession`).

Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9, S1/S2 Speech+Happy,
MVP_thin² VK voice E2E (2026-06-23), Whisper systemd на ubuntu-home,
async callback + TTS dual channel (2026-07-05), Phase 6 focus routing
(2026-07-05), voice-agent-mac full loop E2E (2026-07-17), backend snapshot
в git (2026-07-18) — детали в CHANGELOG.

---

## voice-agent-mac — доводка после E2E green

Loop работает: mic → mlx-whisper local → VDS → inject в Claude-сессию →
Yandex TTS → mac speaker.

- [ ] **E2E dogfood** — живая проверка full loop, 5 фраз подряд без ручного
      вмешательства. Окружение восстановлено 2026-08-01 (`install-mac.sh`):
      venv `~/.venvs/voice-agent` + mlx-whisper, ffmpeg 8.1.2, t3 в `~/bin`,
      враппер `~/bin/voice-agent-t3`.
      ⚠️ **Запускать только локально в Terminal.app на маке.** Через ssh
      re-exec в Aqua-домен падает с `Could not switch to audit session:
      Operation not permitted`, когда экран заблокирован — а без Aqua нет
      микрофона. Я проверить loop сам не могу, нужен ты за компом
- [ ] **Whisper accuracy — разметить корпус.** Harness готов
      ([`bench/whisper-accuracy/`](../bench/whisper-accuracy/README.md)), 24 клипа
      прогнаны через turbo, аудио выложено. Осталось руками заполнить `truth` в
      `ground-truth.jsonl` (слушать по ссылкам) → `./run.py report` даст WER.
      Sergey, это ~5 минут прослушивания
- [ ] **Whisper accuracy на боевых фразах** — текущий корпус весь тестовый
      («тестовое сообщение», «проверка связи»), WER по нему занижен. Нужны
      реальные RU+EN mixed запросы с техтерминами. Накопится сам при dogfood
- [ ] **Починить `Веронись` / `Вертись`** — устойчивые ошибки turbo на
      командах возврата к диспетчеру. Промпт их НЕ лечит (проверено
      2026-08-01), нужен другой подход: постобработка по словарю команд либо
      смена модели на VK-пути. Эти две фразы — рабочие команды, не тесты
- [ ] **`initial_prompt` перенести в config.json** — сейчас зашит в
      `t3-mac-fire-and-poll.py`, в конфиге его нет (проверено 2026-08-01),
      хотя код умеет читать оттуда
- [ ] **Stop hook — живая проверка после фикса** (2026-08-01 логика починена,
      7 тестов green, но E2E с реальным маком не гонялся). Done: голос → ответ
      с tool-вызовами внутри → TTS прочитал финальный текст
- [ ] **Deploy как daemon** — script одноразовый (record 5s → … → exit).
      Loop + launchd plist для always-on. Done: plist загружен, переживает reboot
- [ ] **t3 permanent path** — сейчас `/tmp/`, теряется на reboot. `install-mac.sh`
      → `~/bin/t3-mac-fire-and-poll.py`. Делать если пришлось scp'ить 2+ раза
- [!] **Wake word Porcupine «Алёнка»** (US-1) — blocked: нужен access key +
      train keyword (console.picovoice.ai, ~5 мин). Сейчас запуск вручную

## mac-home — окружение

- [ ] `sudo pmset -a sleep 0 disksleep 0 tcpkeepalive 1` — сейчас sleep=5,
      засыпает при закрытой крышке (см. `reference_mac_home_clamshell`)
- [ ] Screen Sharing daemon kickstart после macOS update (S5900 не listen)
- [ ] Mount voice-repo через sshfs (либо отдельный клон)
- [ ] Удалить spike-артефакты `/tmp/spike-hb/`

## Phase 6 F5 — pattern analyzer

Spec проверен на живых данных 2026-08-01 и поправлен (v1.0.0):
[`docs/voice-patterns.md`](../docs/voice-patterns.md). Запуск отложен —
в `audit.jsonl` 26 записей и все тестовые, порог = 100 нетестовых.

- [ ] Прогнать анализ когда накопится корпус. Проверка порога — команда
      в секции Preconditions спека

---

## Open questions / risks (live)

- VK rate limit / ToS — Sergey ↔ bot DM only, не group. ~100 msg/day fine.
  См. memory `reference_vk_bot_contracts.md`
- VK `audio_message_transcript` async event skip'ается в MVP — Whisper всегда
  работает когда `state != "done"`. Перепроверить если Whisper под нагрузкой
- Audit JSONL eviction policy = NONE (Phase 0 SP3). ~180KB/msg, OK на год
