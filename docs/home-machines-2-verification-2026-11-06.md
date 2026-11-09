# Проверка home-machines 2.0.0 из voice — 06.11.2026

[README — вход](../README.md) · [Индекс документов](INDEX.md) ·
[Текущие задачи](../.claude/TASKS.md) · [Карта переноса правил](project-rules-migration.md)

Поручение agentops по Sergey: `01a1b188-23f8-7e84-827f-41d638ed1816`,
request `f54b3d38-3a70-46b9-95da-0274f2503076`.

**Итог: BLOCKED — Windows занята интерактивным пользователем `serg`.**
Реальных переключений и перезагрузок не выполнялось. Конечная Ubuntu и
проверка STT под hold не достигнуты, а не объявлены исправными по старым тестам.

## Критерии

| Проверка | Результат | Основание |
|---|---|---|
| Новая description в активном каталоге | PASS | В текущем списке skills есть расширенная description про authorized work, ubuntu-home, win-home, GPU и whisper/STT |
| Файл навыка | PASS | Прочитан `/root/.agents/skills/home-machines/SKILL.md`, версия 2.0.0; HEAD agentops `d035685` |
| Автовыбор по обычному запросу «нужен whisper/STT» | NOT TESTED | Этот запрос явно называет home-machines; ручное чтение не доказывает самостоятельный выбор. Новые сессии для изоляции не создавались |
| `os-switch.sh detect` | PASS | До WoL `none`, rc 1; после WoL `windows`, rc 0; повтор подтверждён |
| WoL | PASS с ограничением | Пакет доставлен через MikroTik ether3, rc 0; после него Windows стала отвечать по SSH. Это не переключение ОС и не доказательство, что изначально был именно сон |
| Проверка занятости | BLOCKED | `query user`: `serg`, `console`, ID 1, «Активно», бездействие «отсутствует»; Steam/steamwebhelper запущены. CPU в Get-Process накопительный, текущую игру из него не выводим |
| Lease | Наблюдение | holder `sergey`, причина «переключение в windows», возраст около 6 ч 52 мин; возраст не использован как разрешение на перезагрузку. Аренда не переписывалась |
| Реальное OS switching | NOT TESTED — BLOCKED | Занятую машину не перезагружали, `--force` и подмена holder запрещены |
| Конечная Ubuntu, foreground hold и реальный `/transcribe` | NOT TESTED — BLOCKED | Текущая ОС Windows; GPU/STT-тест не запускался на занятом dual-boot хосте. `/health` не выдавался за доказательство |

## Фактические команды и время UTC

- 15:46:50 — `HOST_LEASE_HOLDER=voice os-switch.sh detect`: `none`, rc 1,
  6.07 с. Это отсутствие подтверждённой ОС, не диагноз сна.
- 15:48:12 — `wake-lan.sh --input-json wake-input.json` с
  `{"machine":"ubuntu-home"}`: rc 0, 4.35 с, WoL отправлен.
- 15:48:18 — detect после WoL: `none`, rc 1, 6.18 с.
- 15:48:26 — повтор detect: `windows`, rc 0, 2.51 с.
- 15:49:42 — повторная проверка: `windows`, rc 0, 2.77 с.
- 15:49:44 — `ssh ... win-home 'query user'`: таблица активной console-сессии
  `serg`; rc **1**, таблица непустая. Windows выдаёт CP866; диагностический
  runner был исправлен после ошибки чтения как UTF-8. Это ошибка runner,
  не сбой определения ОС или отказ переключателя.
- 15:49:47 — bounded PowerShell read-only: boot
  `2026-11-06T05:59:00.5000000Z`, процессы и established SSH, rc 0, 3.0 с.
  Загрузка до WoL подтверждает, что нового boot в рамках проверки не было.

SSH и Windows после WoL доступны. Ошибка inference не диагностировалась:
проверка не дошла до inference. На host нет нового агентского задания,
сессий, изменений Happy, lease или конфигурации. При подготовке прочитаны
ADR-0005, GPU runbook, текущие os-switch.sh/with-host.sh.

## Продолжение

Владелец следующего шага — agentops: повторить live-проверку, когда машина
освободится и это будет подтверждено потребителями/интерактивным входом,
а не только истечением аренды. Если стартовая ОС Windows и свободна —
проверить безопасный переход в Ubuntu, затем bounded реальную речь через
`/transcribe` внутри одного foreground `with-host.sh --hold ubuntu-home`.
Если стартовая Ubuntu, round trip допустим только после такой же проверки.
Не использовать `--force` для получения PASS.

Доказательства этой попытки приложены к ответному inbox: metadata.json,
initial-occupancy.json, wake-probe.json, occupancy.json, lease.json.
Исходные рабочие файлы — `/tmp/voice-home-machines-2-check/`; копии вложений
сохраняются в inbox независимо от дальнейшей жизни /tmp.
