# Продолжение voice после 09.11.2026

[README](../../README.md) · [TASKS](../TASKS.md) · [CHANGELOG](../CHANGELOG.md) · [Индекс](../../docs/INDEX.md)

## Контекст

Sergey завершил текущую сессию и перенёс оставшуюся работу в следующую.
Разрешил закоммитить все накопленные изменения и подготовить этот handoff.
Cwd `/root/projects/voice`, ветка `main`.
[vendor:codex] исходный native ID `01a1a0aa-8d55-7080-8f57-59b7db516d40`,
provider openai, metadata key `codex:01a1a0aa-8d55-7080-8f57-59b7db516d40`.
Identity и cwd сверены через resolve_session_identity. Lifecycle mutation
недоступна в текущем каталоге инструментов, close в sessions-db не записан.
Новая сессия или runtime автоматически не создавались.

## Ссылки

- Миссия и core/feature принципы в [VISION](../../VISION.md), направления
  в [STRATEGY](../../STRATEGY.md), вход для человека и агента в README.
- Актуальные проектные правила в [AGENTS](../../AGENTS.md), исторический
  [vendor:claude] CLAUDE.md направляет туда. [Карта миграции](../../docs/project-rules-migration.md).
- [Остаток 30.10](2026-11-07-from-claude-cf80bea0.md) с точными источниками.
- Приватные результаты встреч в `/srv/voice-private/live/INDEX.md`,
  кандидаты 02–05.11 в `/srv/voice-private/recovery-2026-11-05/action-candidates.md`,
  разбор iOS-комьюнити в `/srv/voice-private/live/ios-community-2026-11-06/`.
- [OBS и эфир](../../backend/voice-service/deploy/live-transcribe/OPERATIONS.md),
  [OS shortcuts](../../docs/home-os-shortcuts.md),
  [проверка home-machines](../../docs/home-machines-2-verification-2026-11-06.md).

## Что важно помнить

OBS на mac-work был закрыт. В этой сессии запущен через open -a OBS.
Последние status и inputs успешны, запись не идёт. Видны микрофон,
захват экрана и системного звука. Реальные уровни звука и кадр ещё проверить.
Автоматического старта записи по времени нет. Запись приоритетнее STT.
Во время эфира голосом молчать, алерты нейтральным звуком и UI.
В последнем локальном process scan live_tail и задания транскрипции отсутствовали.
OBS остаётся запущенным на Mac, новый хвост эфира здесь не запускался.

[vendor:codex] lib_inject.sh пока проверяет native identity через
[vendor:happy] readHappyState и требует Happy SID. Этот код работал 06.11,
переезд на отдельный демон требует нового inject-native из agentops.
Inbox `01a1bbc7-2d31-762b-a7d7-c98f067e55fe` сохранён в TASKS, ack означает
принятие обязательства. Приёмка — idle Codex, busy с кодом 5 и сохранением
сообщения, контроль Claude-пути, голосовой ответ. Перед реализацией читать
`/root/projects/agentops/docs/codex-native-transport.md` и актуальный контракт.

Остаток 30.10 и новая доставка отложены по явному решению Sergey.
Исходные входящие ack, ответ agentops доставлен как
`01a1bf4b-4052-78b6-8ae1-3feb462b8bbc`. Старые незакрытые входящие миграции
сохраняются, свежий inbox проверить в следующей сессии.

Приёмка home-machines 06.11 упёрлась в активную Windows-консоль serg.
Перед использованием снова проверить ОС/занятость по skill home-machines.
GPU подтвердить реальным /transcribe под foreground hold. Старый блокер
не доказывает нынешнюю занятость. После MLX работы на mac-home wrapper
вернул 143, хотя оба JSON получены. Доказательство в coverage.json iOS-разбора.

Сводки 02–05.11 ждут проверки актуальности Sergey. Передача и исполнение
кандидатов из встреч требуют его решения. Ревизия harness по миссии остаётся
открытой в существующем TASKS.

## Проверки и Git

Перед полным коммитом повторены 4 injection-теста и 5 shortcut-тестов,
все прошли. Bash syntax live_tail/lib_inject/winup/windown и diff --check
прошли. Это локальные проверки с подменой внешних границ, живой native/VK
smoke остаётся отдельной задачей.
Предыдущий doc-checkpoint `1dd7164`. Полный коммит включает накопленную
документацию, снимки правил и миссии, live injection, OS shortcuts и тесты.
Итоговый SHA доступен в git log. Push требует согласия Sergey.

## Первый шаг

Прочитать README, AGENTS и этот handoff, проверить свежий inbox.
Если дейлик актуален, проверить OBS status на mac-work, кадр и оба источника
звука, получить сигнал старта от Sergey, подтвердить рост записи по файлу.
Для live STT проверить домашнюю машину по skill и реальную инференс-пробу.
Адресацию чанков в новый тред проверить по действующему native-контракту.
После записи вернуться к переносу доставки и хвосту 30.10 из TASKS.
