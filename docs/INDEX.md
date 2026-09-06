# docs/ — voice

Спеки и планы. История сессий — [`.claude/CHANGELOG.md`](../.claude/CHANGELOG.md),
открытые задачи — [`.claude/TASKS.md`](../.claude/TASKS.md), отложенное —
[`.claude/BACKLOG.md`](../.claude/BACKLOG.md).

## Активное

- [Где что крутится](where-runs-what.md) — карта прода: какая машина за что
  отвечает, два разных Whisper (ubuntu-home для VK, mac-home для микрофона),
  грабли dual-boot, как восстановить потерянное сообщение
- [voice-agent-mac MVP plan](voice-agent-mac-mvp-plan.md) — голосовой агент на
  mac-home (whisper local → Claude → TTS). E2E green 2026-07-17. ⚠️ список
  T1–T12 внутри описывает Fable-standalone архитектуру, которая по факту
  заменена inject-loop'ом — см. BACKLOG
- [Live-транскрипция](live-transcribe.md) — расшифровка системного звука для
  конференций и созвонов: замеры скорости, выбор машины, режимы приватности
- [voice patterns (F5)](voice-patterns.md) — post-hoc анализ войс-запросов
  из `audit.jsonl`. Запускать при ≥100 нетестовых записей, сейчас 26
- [Станция как устройство ввода](alice-skill-input.md) — ресёрч навыка Алисы:
  почему таймаут 4.5 с нам не мешает, что уже готово, чего не заменяет
- [mac-home setup](mac-home-setup.md) — dev-окружение клиента на mac-home

## Phase 7 — MCU wearable (не стартовало, блокер — гарнитура)

- [MCU client](mcu-client.md) — полная архитектура носимого клиента:
  CoreS3 SE + Module Audio + Kenwood K1 + BC-гарнитура
- [macOS PTT MVP spec](macos-ptt-mvp-spec.md) — UX-прототип push-to-talk,
  делается до траты денег на железо
- [macOS PTT week log](macos-ptt-week-log.md) — шаблон недельного
  dogfooding-лога к спеку выше

## Бенчмарки

- [Whisper / Gemma / Apple Speech benchmark plan](whisper-benchmark-plan.md) —
  методология из HYP-028, корпус quiet/noisy, GSM-band emulation. Отложен:
  MVP работает на large-v3
