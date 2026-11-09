# docs/ — voice

[README — вход](../README.md) · [Стратегия](../STRATEGY.md)

Спеки и планы. История сессий — [`.claude/CHANGELOG.md`](../.claude/CHANGELOG.md),
открытые задачи — [`.claude/TASKS.md`](../.claude/TASKS.md), отложенное —
[`.claude/BACKLOG.md`](../.claude/BACKLOG.md).

## Уровни карты

[Правила проектной сессии](../AGENTS.md) — обязательная связь решений
с миссией и сопровождение навигации.
[Карта переноса правил](project-rules-migration.md) — источники, снимки и
непроверенные остатки миграции.

[README — основная точка входа](../README.md) →
[миссия и принципы](../VISION.md) → [стратегия](../STRATEGY.md) →
[текущие задачи](../.claude/TASKS.md).

Ниже — устройство, обоснования и история технических решений. Даты и старые
статусы в документах — свидетельства прошлых проверок; сегодняшнюю готовность
Codex/runtime они не подтверждают.

## Методология

- [Промпт: миссия → стратегия → тактика](mission-strategy-method-prompt.md) —
  прожарка миссии, core/feature, проверка гипотез, упрощение и карта документов;
  пример применения в voice включён.

## Контракты, проверка и исторические итерации

- [Backend contract](../specs/backend-protocol.md) — независимый интерфейс.
- [VK MVP: сценарии](../specs/vk-bot-mvp.md) и [отчёт spike](../specs/vk-bot-mvp-spike-report.md).
- [TDD-стратегия](../.claude/TESTING.md) — защита контрактов.
- [MVP](../MVP.md) — история этапов.
- [Deployment backend](../backend/voice-service/deploy/README.md),
  [STT-сервер](../backend/voice-service/deploy/whisper-server/README.md),
  [live-transcribe deployment](../backend/voice-service/deploy/live-transcribe/README.md),
  [врапперы ответа](../backend/voice-service/deploy/vds-wrappers/README.md).
- Клиенты: [Mac voice-agent](../clients/voice-agent-mac/README.md),
  [macOS PTT](../clients/macos-ptt/README.md), [iOS](../iOS/README.md).

- [Остаток дейлика 30.10](../.claude/handoff/2026-11-07-from-claude-cf80bea0.md) — источник и следующий шаг.

- [Handoff следующей сессии](../.claude/handoff/2026-11-09-next-session.md) — OBS, native-доставка, остатки и проверки.

## Активное

- [Приёмка home-machines 2.0.0 из voice](home-machines-2-verification-2026-11-06.md) —
  detect/WoL проверены, OS-switch/STT заблокированы активным Windows-сеансом.


- [Короткие команды winup/windown на VDS](home-os-shortcuts.md) — существующий
  OS-switch без запуска сессий; отличие от человеческих команд на Mac.


- [Где что крутится](where-runs-what.md) — карта прода: какая машина за что
  отвечает, два разных Whisper (ubuntu-home для VK, mac-home для микрофона),
  грабли dual-boot, как восстановить потерянное сообщение
- [voice-agent-mac MVP plan](voice-agent-mac-mvp-plan.md) — голосовой агент на
  mac-home (whisper local → Claude → TTS). E2E green 2026-07-17. ⚠️ список
  T1–T12 внутри описывает Fable-standalone архитектуру, которая по факту
  заменена inject-loop'ом — см. BACKLOG
- [Live-транскрипция: операционка](../backend/voice-service/deploy/live-transcribe/OPERATIONS.md)
  — управление хвостом, параметры тюнинга, смена слушателя, скриншоты
- [Live-транскрипция](live-transcribe.md) — расшифровка системного звука для
  конференций и созвонов: замеры скорости, выбор машины, режимы приватности
- [Инспекция: дубль live-transcribe против скиллов](inspection-live-transcribe-duplication.md)
  — четыре артефакта на один цикл, шесть расхождений по фактам в глобальной
  доке (нянька, `pkill`, дорожки, чанк, промпт, отправка сводки) и предложение
  развязки; правки глобального контура ждут решения Sergey
- [Инцидент 23.10: 15 минут эфира без распознавания](incident-2026-10-23-whisper-sleep.md)
  — ubuntu-home заснула по простою, нянька этого не ловит; что починено и что
  осталось
- [Глоссарий STT](stt-glossary.md) — источник для `initial_prompt` и блок-листа
  фильтра: домен, имена, устойчивый мусор. Промпт собирается из него
  `bench/work/make-prompt.sh`, руками не правится
- [Кто говорит: разметка по спикерам](diarization.md) — две дорожки OBS (живое
  «ты против остальных», без ML) + диаризация голосов после эфира на
  ubuntu-home; калибровка порога, почему не pyannote
- [Разбор чужого промпта «Разборщик встреч»](prompt-razbor-vstrech-analysis.md)
  — что сделано хорошо (цитаты-основания, чек-лист, эскалация), чего нет
  (замеров, версии), сравнение с нашим пайплайном, что берём себе
- [Транскрибация: идеи и задачи 10.2026](transcribe-roadmap-2026-10.md) — что
  родилось после дейлика, груминга и практикума 06.10; задачи T1-T6 с оценками
- [voice patterns (F5)](voice-patterns.md) — post-hoc анализ войс-запросов
  из `audit.jsonl`. Запускать при ≥100 нетестовых записей, сейчас 26
- [Станция как устройство ввода](alice-skill-input.md) — ресёрч навыка Алисы:
  почему таймаут 4.5 с нам не мешает, что уже готово, чего не заменяет
- [mac-home setup](mac-home-setup.md) — dev-окружение клиента на mac-home
- [Бэкап конспектов](backup-voice-notes.md) — gpg-архив `/srv/voice-private`
  ночью, офсайт на WebDAV через канал agentops; почему не git

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

- [Тонкий голосовой клиент: Zello против SIP](thin-voice-client-research.md) —
  чем заменить колонку на телефоне и отложить носимый девайс; два спайка по
  вечеру каждый

## Планы

- [Пуш на колонку через навык умного дома](plans/2026-10-04-alice-smart-home-push.md) —
  виртуальная лампочка + сценарий «звук на Станции», чтобы колонка сама
  подавала сигнал о новом сообщении в очереди
