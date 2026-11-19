# Checkpoint voice — 19.11.2026

[README](../../README.md) · [Индекс](../../docs/INDEX.md) · [TASKS](../TASKS.md) · [CHANGELOG](../CHANGELOG.md).

## Контекст

Документационный checkpoint по явному вызову Sergey `endsession checkpoint`.
Текущая сессия и runtime не закрываются, новый runtime не создаётся.
Направление VISION/STRATEGY — надёжная запись и сохранение контекста встреч.
Cwd `/root/projects/voice`, ветка `main`, исходный HEAD `82d9127`.

[vendor:codex] Runtime `codex`, provider `openai`, native ID
`01a1e362-5740-70c3-bf6c-1cf23881a20d`, metadata key
`codex:01a1e362-5740-70c3-bf6c-1cf23881a20d`.
Read-only resolve_session_identity подтвердил cwd и original_available=true.
Lifecycle, архивирование и summary в sessions-db не менялись. Общий daemon
не останавливался; checkpoint не означает остановку текущего native runtime.

## Ссылки

- [Индекс встреч](/srv/voice-private/avito/MEETINGS.md).
- [Индекс расшифровок](/srv/voice-private/live/INDEX.md).
- [Груминг19.11: контекст и источники](/srv/voice-private/live/grooming-2026-11-19/checkpoint.md).
- [Вопросы и хронология груминга](/srv/voice-private/live/grooming-2026-11-19/open-questions.md).
- [Живой текст](</srv/voice-private/live/2026-11-19 12-46-38.md>).
- [Проверка собственных удержаний](/srv/voice-private/live/grooming-2026-11-19/checkpoint-holds-check.txt).
- [Дейлик19.11](</srv/voice-private/live/2026-11-19 12-02-33.complete.md>).
- [Предыдущий checkpoint SIP](2026-11-17-voice-checkpoint.md).

## Что важно помнить

Полностью повторно груминг не распознавать — последнее прямое указание Sergey.
Существующие живые блоки сохранены; последнее окно96:30–97:00, необработанный
остаток16,9с. Сам исходник на mac-work сохранён. Полный повтор до коррекции
успел отправить первую дорожку на Whisper, но прерван без результата.
Локального и Mac-процесса больше нет; остановка вычислений уже принятого
HTTP-запроса внутри общего Whisper отдельно не подтверждена. Сервис не трогали.
Live runner завершился0. Relay PID956050 остановлен. Собственные удержания
проверены отдельно; устаревшее with-host-1745898 снято после проверки отсутствия
его владельца. Общий сон/питание не менялись.

Дейлик уже передан в Avito, inbox `01a1f2ee-ba5e-7a94-bb03-03bdca07d33a`,
accepted; копии ранее проверены. Груминг отдельно не отправляли. Нельзя выдавать
сообщение коллеги в записи за разрешение общаться от имени Sergey.

Рабочее дерево содержит незакоммиченный параллельный SIP/voice WIP:
`main.swift`, mac-client installer/player/reply scripts, env example,
новые `AliceNativeDelivery.swift` и `AliceNativeDeliveryTests.swift`.
Также менялись BACKLOG, TASKS, CHANGELOG, handoff15/17.11, docs/INDEX и
thin-voice-client-research. Эти изменения сохранены, не объявлены проверенными
этим checkpoint. До checkpoint незапушенных коммитов относительно upstream
не было. Разрешённый doc-коммит этого checkpoint включает только данный новый
handoff; остальные документы остаются WIP, чтобы не захватить посторонние правки.
Push не разрешён и не выполняется. Исходные встречи приватны и остаются вне Git.

Проверены существование/UTF-8 документов и ссылки индексов, отсутствие своих
обработчиков, фактический выход live0, отсутствие результата полного повтора,
исходная native identity. Код не менялся в checkpoint, тесты не запускались.

## Первый шаг

При продолжении контекста Avito открыть приватный checkpoint и существующие
вопросы, работать по имеющемуся тексту и записи. Не запускать полный STT.
Уточнение продуктовых решений/отправка груминга в inbox остаются отдельными
действиями по действующему поручению. Если работа продолжается по SIP,
использовать checkpoint17.11 и текущие TASKS; не смешивать эти направления.
