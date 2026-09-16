# Управление живой транскрипцией — операционка

Для сессии, которая ведёт конференцию/созвоны. Написано при передаче
управления 15.09.2026; архитектура и обоснования — [`docs/live-transcribe.md`](../../../../docs/live-transcribe.md).

## Что крутится

Хвост живёт в tmux-сессии **`live-tail`** на VDS — не привязан ни к одной
Claude-сессии, переживает их закрытие.

```bash
tmux ls | grep live-tail                # жив?
tail -5 /srv/voice-out/live/tail.log    # что делает
tmux kill-session -t live-tail          # остановить
```

Запустить (одна команда, параметры в env):

```bash
tmux kill-session -t live-tail 2>/dev/null; tmux new-session -d -s live-tail \
  "VOICE_REC_DIR='\$HOME/Movies' \
   VOICE_CHUNK_S=15 \
   VOICE_INJECT_EVERY=2 \
   VOICE_INJECT_SID=<sid сессии-слушателя> \
   VOICE_PROMPT_FILE=/root/projects/voice/bench/podlodka/2026-09/prompt.txt \
   /root/projects/voice/backend/voice-service/deploy/live-transcribe/live_tail.sh \
   mac-work /srv/voice-out/live >> /srv/voice-out/live/tail.log 2>&1"
```

Хвост дежурит постоянно: Sergey жмёт запись в OBS → конспект пошёл сам;
остановил запись → через полторы минуты конспект закрыт, хвост ждёт
следующую. Перезапускать между записями не надо.

## Цикл одного доклада

1. Получить лист ожидания от myRep (приходит cross-session сообщением)
2. Передать сессии-слушателю контекст доклада + лист (инжектом; НЕ угадывать
   доклад по расписанию — оно плывёт, вчера на этом ошиблись)
3. Sergey жмёт запись — дальше само
4. После записи: конспект в `/srv/voice-out/live/<имя записи>.md`, вопросы
   в `questions.md` там же
5. Скриншоты: забрать с мака, вклеить, журнал обновить (ниже)

## Параметры тюнинга (env при запуске tmux-сессии)

| параметр | сейчас | что делает |
|---|---|---|
| `VOICE_CHUNK_S` | 15 | длина чанка распознавания, сек. Меньше — быстрее видно текст, но короче контекст для whisper (ниже 15 не стоит: рвёт фразы) |
| `VOICE_INJECT_EVERY` | 2 | сколько чанков копить до инжекта. 15×2 = блок 30 с. Больше — реже дёргается слушатель, но позже видит |
| `VOICE_INJECT_SID` | sid слушателя | куда летят блоки. **Новая сессия-слушатель = поменять здесь и перезапустить tmux** |
| `VOICE_PROMPT_FILE` | prompt.txt конференции | словарь техтерминов для whisper. Читается на старте — после правки перезапустить tmux |
| `VOICE_REC_DIR` | `$HOME/Movies` | где OBS пишет записи |
| `VOICE_WHISPER_URL` | CUDA ubuntu-home | движок распознавания; если ubuntu-home лёг — убрать переменную, но локального fallback в скрипте нет, чинить хост (WoL: `/root/projects/agentops/bin/wake-lan.sh ubuntu-home`, грабли dual-boot — `docs/where-runs-what.md`) |

Смена любого параметра = перезапуск tmux-сессии командой выше. Идущую
запись это НЕ ломает совсем: обработанные-но-недоинжекченные чанки не
теряются в конспекте (файл дописан), но недоинжекченный буфер пропадёт, и
**распознавание начнётся с нуля по позиции** — то есть перезапускать лучше
между записями, не посреди доклада.

## Если создали новую сессию-слушателя

1. Взять её sid: `jq -r '.sessions | to_entries[] | select(.value.metadata.path=="/root/projects/voice" and .value.metadata.lifecycleState=="running") | .key' ~/.happy/sessions.json`
2. Передать ей промпт слушателя (роль, правила молчания, «голосом никогда»,
   текущий лист ожидания) — образец в истории этой сессии или собрать из
   `docs/live-transcribe.md` раздел «Финальный flow»
3. Перезапустить tmux с новым `VOICE_INJECT_SID`

## Обработка речи после whisper

Сейчас блоки идут в слушателя СЫРЫМИ (whisper-текст читаем, отдельное
сглаживание не понадобилось). Если захочется прогонять через субагента
(сглаживание, перевод терминов) — это делает слушатель у себя, не хвост:
хвост намеренно тупой, вся смысловая работа в сессии.

## Скриншоты

Sergey жмёт `⌘⇧Z` (хоткей «Скриншот вывода» OBS) → снимки в `~/Movies`.

После записи:

```bash
D=/root/projects/voice/bench/podlodka/2026-09
scp 'mac-work:~/Movies/Screenshot <дата>*.png' $D/shots/
scp mac-work:'~/Movies/processed.md' $D/shots/processed.md   # забрать правки Sergey
cp "/srv/voice-out/live/<запись>.md" $D/transcripts/<имя>.md
backend/voice-service/deploy/live-transcribe/attach_screenshots.py \
  $D/transcripts/<имя>.md $D/shots --start "<дата время из имени записи>"
scp $D/shots/processed.md mac-work:'~/Movies/processed.md'   # вернуть журнал
```

Журнал `processed.md` — регулятор: строка есть = снимок обработан и не
клеится повторно; Sergey может удалять/добавлять строки руками.

## Известные грабли

- **Не пайпить хвост через grep/rtk** — rtk режет вывод на 200 строках и
  убивает процесс. Лог только в файл (уже так)
- **zsh на маке** роняет команды с несматченным глобом — удалённые команды
  через `sh -c` или `find`
- **mkv/mov читается недописанным**, ffprobe занижает длительность безопасно
- **Записи прошлых месяцев** в `~/Movies` — хвост берёт только файл свежее
  10 минут
- Конец записи = 90 с без роста файла; пауза в докладе длиннее — хвост
  закроет конспект раньше времени, следующая запись создаст новый

## Запись в дороге и не с mac-work (проверено 2026-09-15)

**mac-work остаётся доступен на мобильном интернете.** Туннель держит сам
мак наружу (`ssh -N -R 2223:localhost:22 ufohosting`, LaunchAgent
`com.sgpopyvanov.reverse-tunnel`) — VDS достаёт его из любой сети. Отдельно
ничего настраивать не надо, хвост работает как дома.

Если источник звука — **mac-home** (личный мак, например собеседование):

- ставить ничего не нужно: OBS, ffmpeg, autossh, brew там уже есть.
  BlackHole **не требуется** — OBS снимает системный звук через
  ScreenCaptureKit, как на mac-work. Драйвер нужен только если понадобится
  маршрутизация звука мимо OBS
- вне домашней сети `ssh mac-home` (192.168.88.35, через WG) мёртв. Мак сам
  поднимает обратный туннель:
  ```bash
  autossh -M 0 -f -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no \
    -i ~/.ssh/ufohosting -R 2222:localhost:22 root@ufohosting
  ```
  На VDS для него есть алиас `mac-home-tun` (localhost:2222), хвост
  запускается с ним вместо `mac-work`. Исторический LaunchAgent —
  `.claude/attic/com.flyer2001.reverse-tunnel.plist`
- в GUI один раз: источник **macOS Audio Capture (Screen Capture)**,
  разрешение Screen & System Audio Recording, путь записи `~/Movies`, хоткей
  скриншота `⌘⇧Z`. Встроенный микрофон на mac-home мёртв — для живого голоса
  только внешняя гарнитура

**VNC не носит звук.** Зайти по Screen Sharing на удалённый мак и слушать
там созвон нельзя — звук остаётся на той машине. OBS ставится там, где
реально играет звук.

**Трафик живого режима** — сырой wav 16 кГц, ~32 кБ/с вверх с мака. LTE
тянет; при слабой связи разумнее не стримить, а забрать звук после:

```bash
ssh mac-work 'export PATH=/opt/homebrew/bin:$PATH; ffmpeg -v error \
  -i ~/Movies/<запись>.mov -vn -ar 16000 -ac 1 -c:a libopus -b:a 24k /tmp/talk.opus'
scp mac-work:/tmp/talk.opus /srv/voice-out/
```

~11 МБ на час. Запись всегда лежит локально на маке, так что живой хвост —
best-effort, а не единственный шанс.

[← README.md](README.md)
